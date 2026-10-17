import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'finance_models.dart';
import 'installment_models.dart';

/// This local prototype is NOT cloud-synced, backed up, or production storage.
abstract class TransactionStore {
  Future<List<FinanceEntry>> load();
  Future<void> save(List<FinanceEntry> entries);
}

/// Both entries and installment payment references live in one versioned
/// snapshot so a payment cannot be saved separately from its withdrawal.
abstract class LedgerStore implements TransactionStore {
  Future<InstallmentLedger> loadLedger();
  Future<void> saveLedger(InstallmentLedger ledger);
}

abstract class BackupRestorableStore {
  /// Keep the old encrypted snapshot before a confirmed import replaces it.
  Future<void> replaceFromBackup(InstallmentLedger ledger);
  Future<InstallmentLedger?> lastImportRestorePoint();
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

/// Per-account device encrypted preview storage. v1 transaction snapshots are
/// opened without data loss and become v2 (transaction+installment) on write.
class EncryptedTransactionStore implements LedgerStore, BackupRestorableStore {
  EncryptedTransactionStore({
    required String accountScope,
    PrivateStringStorage? storage,
  })  : assert(accountScope.isNotEmpty),
        _key = 'hesabaty_flutter_v2_entries_${accountScope}_v1',
        _storage = storage ?? const DevicePrivateStorage();

  final String _key;
  final PrivateStringStorage _storage;

  String get _restoreKey => '${_key}_pre_import';

  @override
  Future<void> replaceFromBackup(InstallmentLedger ledger) async {
    // Validate the incoming data before touching either storage key.
    _validateLedgerForWrite(ledger);
    final old = await _storage.read(_key);
    if (old != null) {
      // Do not overwrite the only restore point if the original is unreadable.
      _decodeLedger(old);
      await _storage.write(_restoreKey, old);
    }
    await saveLedger(ledger);
  }

  @override
  Future<InstallmentLedger?> lastImportRestorePoint() async {
    final raw = await _storage.read(_restoreKey);
    if (raw == null) return null;
    return _decodeLedger(raw);
  }

  static void _validateLedgerForWrite(InstallmentLedger ledger) {
    final ids = <String>{};
    for (final entry in ledger.entries) {
      if (!ids.add(entry.id)) {
        throw const FormatException('Duplicate transaction ID');
      }
      entry.toJson();
    }
    final planIds = <String>{};
    for (final plan in ledger.installments) {
      if (!planIds.add(plan.id)) {
        throw const FormatException('Duplicate installment ID');
      }
      plan.validate();
    }
    _validateLinks(ledger.entries, ledger.installments);
  }

  @override
  Future<List<FinanceEntry>> load() async => (await loadLedger()).entries;

  @override
  Future<InstallmentLedger> loadLedger() async {
    final raw = await _storage.read(_key);
    if (raw == null) {
      return const InstallmentLedger(entries: [], installments: []);
    }
    return _decodeLedger(raw);
  }

  static InstallmentLedger _decodeLedger(String raw) {
    // Corruption/future schema must never be treated as an empty snapshot.
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        ![1, 2].contains(decoded['schemaVersion']) ||
        decoded['entries'] is! List ||
        (decoded['schemaVersion'] == 2 && decoded['installments'] is! List)) {
      throw const FormatException('Unsupported ledger snapshot version');
    }
    final entries = <FinanceEntry>[];
    final entryIds = <String>{};
    for (final value in decoded['entries'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid transaction object');
      }
      final entry = FinanceEntry.fromJson(value);
      if (!entryIds.add(entry.id)) {
        throw const FormatException('Duplicate transaction ID');
      }
      entries.add(entry);
    }
    final installments = <InstallmentPlan>[];
    final planIds = <String>{};
    if (decoded['schemaVersion'] == 2) {
      for (final item in decoded['installments'] as List) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid installment object');
        }
        final plan = InstallmentPlan.fromJson(item);
        if (!planIds.add(plan.id)) {
          throw const FormatException('Duplicate installment ID');
        }
        installments.add(plan);
      }
    }
    _validateLinks(entries, installments);
    final categories = decoded['customCategories'] ?? [];
    final prefs = decoded['prefs'] ?? <String, dynamic>{};
    final createdAt = decoded['createdAt'] ?? '';
    if (categories is! List ||
        categories.any((value) => value is! String) ||
        prefs is! Map<String, dynamic> ||
        createdAt is! String) {
      throw const FormatException('Invalid saved user preferences');
    }
    return InstallmentLedger(
      entries: entries, installments: installments,
      customCategories: List<String>.from(categories),
      prefs: Map<String, dynamic>.from(prefs),
      createdAt: createdAt,
    );
  }

  static void _validateLinks(
      List<FinanceEntry> entries, List<InstallmentPlan> installments) {
    final byId = {for (final e in entries) e.id: e};
    final paymentReferences = <String>{};
    for (final plan in installments) {
      plan.validate();
      for (final payment in plan.payments) {
        if (!paymentReferences.add(payment.transactionId)) {
          throw const FormatException('One transaction linked to two payments');
        }
        final entry = byId[payment.transactionId];
        if (entry == null ||
            entry.type != EntryType.withdrawal ||
            entry.linkedInstallment != plan.id) {
          throw const FormatException('Broken installment payment link');
        }
      }
    }
    // Transactions formerly linked to a deleted plan are allowed: historical
    // records must remain, but they cannot be reused without explicit unlink.
  }

  @override
  Future<void> save(List<FinanceEntry> entries) async {
    final existing = await loadLedger();
    await saveLedger(existing.withCollections(
      entries: entries,
      installments: existing.installments,
    ));
  }

  @override
  Future<void> saveLedger(InstallmentLedger ledger) async {
    _validateLedgerForWrite(ledger);
    final data = jsonEncode({
      'schemaVersion': 2,
      'entries': ledger.entries.map((e) => e.toJson()).toList(),
      'installments': ledger.installments.map((p) => p.toJson()).toList(),
      'customCategories': ledger.customCategories,
      'prefs': ledger.prefs,
      'createdAt': ledger.createdAt,
    });
    await _storage.write(_key, data);
  }
}
