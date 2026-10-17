import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'finance_models.dart';

/// Transaction storage boundary. The current preview uses protected device
/// storage; it does not sync to Supabase and is not a production finance DB.
abstract class TransactionStore {
  Future<List<FinanceEntry>> load();
  Future<void> save(List<FinanceEntry> entries);
}

abstract class PrivateStringStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DevicePrivateStorage implements PrivateStringStorage {
  const DevicePrivateStorage();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Separate guest and each signed-in account by stable immutable identifiers.
/// Never use email addresses as identity. Never merge accounts implicitly.
class EncryptedTransactionStore implements TransactionStore {
  EncryptedTransactionStore({
    required String accountScope,
    PrivateStringStorage? storage,
  })  : assert(accountScope.isNotEmpty),
        _key = 'hesabaty_flutter_v2_entries_${accountScope}_v1',
        _storage = storage ?? const DevicePrivateStorage();

  final String _key;
  final PrivateStringStorage _storage;

  @override
  Future<List<FinanceEntry>> load() async {
    final raw = await _storage.read(_key);
    if (raw == null) return <FinanceEntry>[];
    // A damaged or future-version snapshot must NEVER be treated as empty,
    // otherwise the next save could overwrite the user's actual records.
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['entries'] is! List) {
      throw const FormatException('Unsupported transaction store format');
    }
    final result = <FinanceEntry>[];
    final ids = <String>{};
    for (final value in decoded['entries'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid transaction object');
      }
      final entry = FinanceEntry.fromJson(value);
      if (!ids.add(entry.id)) {
        throw const FormatException('Duplicate transaction identifier');
      }
      result.add(entry);
    }
    return result;
  }

  @override
  Future<void> save(List<FinanceEntry> entries) async {
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.id)) {
        throw const FormatException('Duplicate transaction identifier');
      }
    }
    final data = jsonEncode({
      'schemaVersion': 1,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    await _storage.write(_key, data);
  }
}
