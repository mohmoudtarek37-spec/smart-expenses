import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/analytics_models.dart';
import 'package:hesabaty/finance/finance_models.dart';

FinanceEntry tx(String id, EntryType type, double amount, int year,
    int month, String category, {bool excluded = false}) =>
    FinanceEntry(
      id: id, type: type, amount: amount,
      date: DateTime(year, month, 10),
      category: category, excluded: excluded,
    );

void main() {
  test('last six months cross calendar year correctly with no fake data', () {
    final analytics = AnalyticsSummary(
      summary: const FinanceSummary([]),
      selectedMonth: DateTime(2026, 2),
      today: DateTime(2026, 10),
    );
    expect(analytics.lastSixMonths.map((e) =>
        '${e.month.year}-${e.month.month}').toList(), [
      '2025-9', '2025-10', '2025-11',
      '2025-12', '2026-1', '2026-2',
    ]);
    expect(analytics.maxChartValue, 1);
    expect(analytics.lastSixMonths.every((m) =>
        m.totals.deposit == 0 && m.totals.withdrawal == 0), isTrue);
  });

  test('previous month comparison calculates increases and partial month', () {
    final analytics = AnalyticsSummary(
      summary: FinanceSummary([
        tx('a', EntryType.withdrawal, 200, 2026, 10, 'مطاعم'),
        tx('b', EntryType.withdrawal, 100, 2026, 9, 'مطاعم'),
      ]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(analytics.comparison.direction, ExpenseDirection.increased);
    expect(analytics.comparison.percentage, 100);
    expect(analytics.comparison.isPartialMonth, isTrue);
    expect(analytics.comparison.describe((n) => n.toString()),
        contains('مقارنة مبدئية'));
  });

  test('decreased and unchanged comparisons have valid percentages', () {
    final data = [
      tx('a', EntryType.withdrawal, 100, 2026, 9, 'مطاعم'),
      tx('b', EntryType.withdrawal, 200, 2026, 8, 'مطاعم'),
    ];
    final lowered = AnalyticsSummary(
      summary: FinanceSummary(data),
      selectedMonth: DateTime(2026, 9),
      today: DateTime(2026, 10, 17),
    );
    expect(lowered.comparison.direction, ExpenseDirection.decreased);
    expect(lowered.comparison.percentage, -50);
    expect(lowered.comparison.isPartialMonth, isFalse);
    final same = AnalyticsSummary(
      summary: FinanceSummary([...data,
        tx('c', EntryType.withdrawal, 100, 2026, 10, 'مطاعم')]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(same.comparison.direction, ExpenseDirection.unchanged);
    expect(same.comparison.percentage, 0);
  });

  test('previous month zero never causes infinity or misleading percent', () {
    final analytics = AnalyticsSummary(
      summary: FinanceSummary([
        tx('first', EntryType.withdrawal, 100, 2026, 10, 'صحة'),
      ]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(analytics.comparison.direction, ExpenseDirection.noComparison);
    expect(analytics.comparison.percentage, isNull);
    expect(analytics.comparison.describe((n) => n.toString()),
        contains('غير متاحة'));
    final empty = AnalyticsSummary(
      summary: const FinanceSummary([]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(empty.comparison.direction, ExpenseDirection.noExpenses);
  });

  test('expense share is undefined without income, may exceed 100%', () {
    final analytics = AnalyticsSummary(
      summary: FinanceSummary([
        tx('a', EntryType.deposit, 50, 2026, 10, 'راتب'),
        tx('b', EntryType.withdrawal, 100, 2026, 10, 'مواصلات'),
      ]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(analytics.spendingShare, 200);
    expect(analytics.current.remaining, -50);
    final zero = AnalyticsSummary(
      summary: FinanceSummary([
        tx('b', EntryType.withdrawal, 100, 2026, 10, 'مواصلات'),
      ]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(zero.spendingShare, isNull);
  });

  test('excluded transactions do not appear in analytics or counts', () {
    final analytics = AnalyticsSummary(
      summary: FinanceSummary([
        tx('a', EntryType.deposit, 500, 2026, 10, 'راتب'),
        tx('b', EntryType.withdrawal, 200, 2026, 10, 'مطاعم'),
        tx('c', EntryType.withdrawal, 900, 2026, 10, 'صحة',
            excluded: true),
        tx('d', EntryType.withdrawal, 70, 2026, 9, 'مواصلات'),
      ]),
      selectedMonth: DateTime(2026, 10),
      today: DateTime(2026, 10, 17),
    );
    expect(analytics.current.withdrawal, 200);
    expect(analytics.current.deposit, 500);
    expect(analytics.current.transactionCount, 2);
    expect(analytics.categories.map((e) => e.key).toList(), ['مطاعم']);
    expect(analytics.maxChartValue, 500);
  });
}
