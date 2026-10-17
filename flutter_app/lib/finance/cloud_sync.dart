import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'backup_codec.dart';
import 'installment_models.dart';

/// A clear limit is essential because receipts are currently inline Data URLs.
class CloudSnapshotBudget {
  static const maxBytes = 8 * 1024 * 1024;

  static int estimateBytes(InstallmentLedger ledger) {
    final envelope = jsonDecode(BackupCodec.encode(ledger))
        as Map<String, dynamic>;
    return utf8.encode(jsonEncode(envelope['data'])).length;
  }

  static bool fits(int bytes) => bytes <= maxBytes;

  static bool nearLimit(int bytes) => bytes >= maxBytes * 3 ~/ 4;
}

class CloudSnapshot {
  const CloudSnapshot({required this.ledger, required this.revision});
  final InstallmentLedger ledger;
  final int revision;
}

class CloudConflict implements Exception {
  const CloudConflict();
  @override
  String toString() => 'Cloud version changed. Reload and review before syncing.';
}

/// User-scoped cloud sync service. All mutations are explicitly initiated by
/// the user in this preview; no implicit merging or overwrites.
/// A stable comparison for JSONB round-trips: key order and transaction
/// ordering cannot make an otherwise unchanged ledger look different.
class LedgerContent {
  static dynamic _sorted(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) {
      return value.map(_sorted).toList();
    }
    return value;
  }

  static String canonical(InstallmentLedger ledger) {
    final entries = ledger.entries.map((entry) => entry.toJson()).toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final plans = ledger.installments.map((plan) => plan.toJson()).toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return jsonEncode(_sorted({
      'entries': entries,
      'installments': plans,
      'customCategories': ledger.customCategories,
      'prefs': ledger.prefs,
      'createdAt': ledger.createdAt,
    }));
  }

  static bool equivalent(InstallmentLedger first, InstallmentLedger second) =>
      canonical(first) == canonical(second);
}

/// Restores cloud records automatically only on a genuinely untouched device.
/// Empty entries can also mean a user intentionally deleted every transaction
/// while offline; a saved revision MUST block automatic restore in that case.
class CloudRestorePolicy {
  static bool isEmpty(InstallmentLedger ledger) =>
      ledger.entries.isEmpty &&
      ledger.installments.isEmpty &&
      ledger.customCategories.isEmpty &&
      ledger.prefs.isEmpty &&
      ledger.createdAt.isEmpty;

  static bool mayRestoreOnLaunch({
    required InstallmentLedger local,
    required int? savedCloudRevision,
  }) => savedCloudRevision == null && isEmpty(local);
}

class CloudFinanceSync {
  CloudFinanceSync(this.client);

  final SupabaseClient client;

  String get _userId {
    final user = client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw StateError('Authentication required for cloud sync.');
    }
    return user.id;
  }

  Future<CloudSnapshot?> fetch() async {
    final userId = _userId;
    final response = await client
        .from('user_snapshots')
        .select('snapshot,revision')
        .eq('user_id', userId)
        .maybeSingle();
    if (_userId != userId) throw StateError('Account changed while loading.');
    if (response == null) return null;
    final revision = response['revision'];
    final raw = response['snapshot'];
    if (revision is! int || revision < 1 ||
        raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid server finance snapshot.');
    }
    final archive = jsonEncode({
      'format': 'hesabaty-backup',
      'appVersion': 'cloud',
      'data': raw,
    });
    final ledger = BackupCodec.decode(archive).ledger;
    return CloudSnapshot(ledger: ledger, revision: revision);
  }

  /// Only caller-supplied expected revision may be used for server writes.
  /// null means create-only; no silent overwrite if a row already exists.
  Future<int> push(InstallmentLedger ledger, {required int? expectedRevision}) async {
    final userId = _userId;
    final archive = jsonDecode(BackupCodec.encode(ledger))
        as Map<String, dynamic>;
    final data = archive['data'] as Map<String, dynamic>;
    final bytes = utf8.encode(jsonEncode(data)).length;
    if (!CloudSnapshotBudget.fits(bytes)) {
      throw const FormatException('Cloud snapshot larger than 8 MB.');
    }
    try {
      final value = await client.rpc(
        'save_hesabaty_snapshot_if_revision',
        params: {
          'p_snapshot': data,
          'p_expected_revision': expectedRevision,
        },
      );
      if (_userId != userId) throw StateError('Account changed while saving.');
      if (value is! int || value < 1) {
        throw const FormatException('Invalid cloud revision.');
      }
      return value;
    } on PostgrestException catch (error) {
      if (error.code == '40001' ||
          error.message.contains('Snapshot changed on another device')) {
        throw const CloudConflict();
      }
      rethrow;
    }
  }
}
