import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/cloud_sync.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  test('empty ledger stays far below 8 MB cap', () {
    const ledger = InstallmentLedger(entries: [], installments: []);
    final bytes = CloudSnapshotBudget.estimateBytes(ledger);
    expect(bytes, greaterThan(0));
    expect(CloudSnapshotBudget.fits(bytes), isTrue);
    expect(CloudSnapshotBudget.nearLimit(bytes), isFalse);
  });
  test('attachments count toward cloud budget', () {
    final ledger = InstallmentLedger(entries: [
      FinanceEntry(id: '1', type: EntryType.withdrawal, amount: 50,
        date: DateTime(2026, 10, 17), category: 'فاتورة',
        receiptDataUrl: 'data:image/png;base64,' +
            List.filled(10000, 'A').join()),
    ], installments: const []);
    expect(CloudSnapshotBudget.estimateBytes(ledger), greaterThan(10000));
    expect(CloudSnapshotBudget.fits(8 * 1024 * 1024 + 1), isFalse);
    expect(CloudSnapshotBudget.nearLimit(6 * 1024 * 1024), isTrue);
  });
}
