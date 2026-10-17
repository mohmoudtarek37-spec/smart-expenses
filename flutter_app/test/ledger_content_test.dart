import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/cloud_sync.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  FinanceEntry e(String id, double amount, {Map<String, dynamic> extra = const {}}) =>
      FinanceEntry(id: id, type: EntryType.withdrawal,
          amount: amount, date: DateTime(2026, 10, 17),
          category: 'مطاعم', extraFields: extra);

  test('equivalent ledgers remain same regardless of transaction order', () {
    final left = InstallmentLedger(entries: [e('a', 50), e('b', 20)],
        installments: const []);
    final right = InstallmentLedger(entries: [e('b', 20), e('a', 50)],
        installments: const []);
    expect(LedgerContent.equivalent(left, right), isTrue);
  });

  test('map key order is irrelevant after a JSONB round trip', () {
    final left = InstallmentLedger(entries: [
      e('x', 30, extra: {'custom': {'a': 1, 'b': 2}})
    ], installments: const []);
    final right = InstallmentLedger(entries: [
      e('x', 30, extra: {'custom': {'b': 2, 'a': 1}})
    ], installments: const []);
    expect(LedgerContent.equivalent(left, right), isTrue);
  });

  test('changed amounts and deleted records are never equal', () {
    final left = InstallmentLedger(entries: [e('x', 30)],
        installments: const []);
    final changed = InstallmentLedger(entries: [e('x', 31)],
        installments: const []);
    const removed = InstallmentLedger(entries: [], installments: []);
    expect(LedgerContent.equivalent(left, changed), isFalse);
    expect(LedgerContent.equivalent(left, removed), isFalse);
  });
}
