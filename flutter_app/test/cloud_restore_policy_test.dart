import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/cloud_sync.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  const pristine = InstallmentLedger(entries: [], installments: []);

  test('new untouched device can restore an existing account', () {
    expect(CloudRestorePolicy.mayRestoreOnLaunch(
      local: pristine, savedCloudRevision: null), isTrue);
  });

  test('deleted last transaction must NOT be restored from stale cloud', () {
    // The local ledger is now empty, but its last uploaded version is known.
    expect(CloudRestorePolicy.mayRestoreOnLaunch(
      local: pristine, savedCloudRevision: 2), isFalse);
  });

  test('unsynced custom categories and preferences are protected', () {
    const prefs = InstallmentLedger(
      entries: [], installments: [], prefs: {'currency': 'EGP'});
    const cats = InstallmentLedger(
      entries: [], installments: [], customCategories: ['مخصص']);
    const createdAt = InstallmentLedger(
      entries: [], installments: [], createdAt: '2026-10-17');
    for (final ledger in [prefs, cats, createdAt]) {
      expect(CloudRestorePolicy.mayRestoreOnLaunch(
        local: ledger, savedCloudRevision: null), isFalse);
      expect(CloudRestorePolicy.isEmpty(ledger), isFalse);
    }
  });

  test('local transaction never overwritten during automatic restore', () {
    final ledger = InstallmentLedger(
      entries: [FinanceEntry(
        id: 'expense', type: EntryType.withdrawal, amount: 50,
        date: DateTime(2026, 10, 17), category: 'شراء',
      )],
      installments: const [],
    );
    expect(CloudRestorePolicy.mayRestoreOnLaunch(
      local: ledger, savedCloudRevision: null), isFalse);
  });
}
