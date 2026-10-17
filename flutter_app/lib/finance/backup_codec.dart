import 'dart:convert';

import 'finance_models.dart';
import 'installment_models.dart';

/// Portable JSON backups compatible with the legacy HTML app's
/// "hesabaty-backup" export envelope. No network calls or automatic import.
class BackupPreview {
  const BackupPreview({
    required this.ledger,
    required this.sourceVersion,
  });

  final InstallmentLedger ledger;
  final String sourceVersion;

  int get transactionCount => ledger.entries.length;
  int get installmentCount => ledger.installments.length;
  int get receiptCount =>
      ledger.entries.where((entry) => entry.receiptDataUrl.isNotEmpty).length;
  int get smsCount =>
      ledger.entries.where((entry) => entry.originalMessage.isNotEmpty).length;
}

class BackupCodec {
  static const maxBackupBytes = 35 * 1024 * 1024;

  static String encode(InstallmentLedger ledger) {
    validate(ledger);
    final now = DateTime.now().toUtc().toIso8601String();
    final data = {
      'schemaVersion': 1,
      'transactions': ledger.entries.map((entry) => entry.toJson()).toList(),
      'installments': ledger.installments.map((plan) => plan.toJson()).toList(),
      'customCategories': ledger.customCategories,
      'prefs': ledger.prefs,
      'createdAt': ledger.createdAt,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'format': 'hesabaty-backup',
      'appVersion': '2.0.0-flutter-preview',
      'exportedAt': now,
      'data': data,
    });
    if (utf8.encode(encoded).length > maxBackupBytes) {
      throw const FormatException(
          'Backup exceeds 35 MB. Export receipts separately first.');
    }
    return encoded;
  }

  static BackupPreview decode(String raw) {
    if (utf8.encode(raw).length > maxBackupBytes) {
      throw const FormatException('Backup exceeds 35 MB');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'hesabaty-backup' ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const FormatException('Not a Hesabaty backup file');
    }
    final data = decoded['data'] as Map<String, dynamic>;
    if (data['schemaVersion'] != 1 ||
        data['transactions'] is! List ||
        data['installments'] is! List) {
      throw const FormatException('Unsupported backup data version');
    }
    final entries = <FinanceEntry>[];
    for (final value in data['transactions'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid transaction in backup');
      }
      entries.add(FinanceEntry.fromJson(value));
    }
    final plans = <InstallmentPlan>[];
    for (final value in data['installments'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid installment in backup');
      }
      // The HTML version sometimes omitted these optional defaults.
      plans.add(InstallmentPlan.fromJson({
        ...value,
        'active': value['active'] ?? true,
        'count': value['count'] ?? 0,
        'payments': value['payments'] ?? <dynamic>[],
      }));
    }
    final categories = data['customCategories'] ?? <dynamic>[];
    final prefs = data['prefs'] ?? <String, dynamic>{};
    final createdAt = data['createdAt'] ?? '';
    if (categories is! List ||
        categories.any((category) => category is! String) ||
        prefs is! Map<String, dynamic> ||
        createdAt is! String) {
      throw const FormatException('Invalid backup preferences');
    }
    final ledger = InstallmentLedger(
      entries: entries,
      installments: plans,
      customCategories: List<String>.from(categories),
      prefs: Map<String, dynamic>.from(prefs),
      createdAt: createdAt,
    );
    validate(ledger);
    return BackupPreview(
      ledger: ledger,
      sourceVersion: decoded['appVersion'] is String
          ? decoded['appVersion'] as String : 'HTML',
    );
  }

  /// Reject conflicting references, duplicates, invalid dates and totals
  /// BEFORE showing the user a confirmation to replace existing records.
  static void validate(InstallmentLedger ledger) {
    final entriesById = <String, FinanceEntry>{};
    for (final entry in ledger.entries) {
      entry.toJson();
      if (entriesById.containsKey(entry.id)) {
        throw const FormatException('Duplicate transaction IDs in backup');
      }
      entriesById[entry.id] = entry;
    }
    final plansById = <String, InstallmentPlan>{};
    final paymentTxIds = <String>{};
    for (final plan in ledger.installments) {
      plan.validate();
      if (plansById.containsKey(plan.id)) {
        throw const FormatException('Duplicate installment IDs in backup');
      }
      plansById[plan.id] = plan;
      for (final payment in plan.payments) {
        if (!paymentTxIds.add(payment.transactionId)) {
          throw const FormatException('One withdrawal used by two payments');
        }
        final entry = entriesById[payment.transactionId];
        if (entry == null ||
            entry.type != EntryType.withdrawal ||
            entry.linkedInstallment != plan.id) {
          throw const FormatException('Broken installment payment reference');
        }
      }
    }
    // Any old extra transaction fields are kept unchanged in FinanceEntry.
    // Failed validation must never write to or reset the local store.
  }
}
