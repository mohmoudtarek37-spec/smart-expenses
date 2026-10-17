import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';

void main() {
  final october = DateTime(2026, 10, 17);
  final finance = FinanceSummary([
    FinanceEntry(id: 'a', type: EntryType.deposit, amount: 1000,
        date: DateTime(2026, 10, 1), category: 'راتب'),
    FinanceEntry(id: 'b', type: EntryType.withdrawal, amount: 250,
        date: DateTime(2026, 10, 16), category: 'مطاعم'),
    FinanceEntry(id: 'c', type: EntryType.withdrawal, amount: 100,
        date: DateTime(2026, 10, 10), category: 'مطاعم'),
    FinanceEntry(id: 'd', type: EntryType.withdrawal, amount: 99,
        date: DateTime(2026, 10, 11), category: 'مواصلات',
        excluded: true),
    FinanceEntry(id: 'e', type: EntryType.withdrawal, amount: 333,
        date: DateTime(2026, 9, 11), category: 'مطاعم'),
  ]);

  test('monthly totals match HTML semantics and ignore excluded entries', () {
    final totals = finance.totals(october);
    expect(totals.deposit, 1000);
    expect(totals.withdrawal, 350);
    expect(totals.remaining, 650);
    expect(totals.spendingPercentage, 35);
    expect(totals.transactionCount, 3);
    expect(finance.monthEntries(october), hasLength(4));
  });

  test('spending ring is bounded at 100%, real ratio is not', () {
    const totals = MonthTotals(deposit: 100, withdrawal: 300,
        transactionCount: 2);
    expect(totals.spendingPercentage, 300);
    expect(totals.ringPercentage, 100);
    const empty = MonthTotals(deposit: 0, withdrawal: 150,
        transactionCount: 1);
    expect(empty.spendingPercentage, 0);
  });

  test('categories only count included expenses in selected month', () {
    final cats = finance.categoryTotals(october);
    expect(cats, hasLength(1));
    expect(cats.first.key, 'مطاعم');
    expect(cats.first.value, 350);
  });

  test('month navigation handles December and leap-year rollover', () {
    expect(shiftMonth(DateTime(2026, 12, 31), 1), DateTime(2027, 1));
    expect(shiftMonth(DateTime(2024, 3, 31), -1), DateTime(2024, 2));
    expect(monthTitle(DateTime(2026, 10)), 'أكتوبر 2026');
  });

  test('recent entries in selected month are newest first', () {
    expect(finance.recent(october).map((entry) => entry.id).toList(),
        ['b', 'd', 'c', 'a']);
    expect(finance.recent(october, limit: 2), hasLength(2));
  });
}
