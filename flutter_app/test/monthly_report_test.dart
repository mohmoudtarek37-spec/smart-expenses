import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/monthly_report.dart';

void main() {
  final month = DateTime(2026, 10);
  FinanceEntry transaction(int day, String id, EntryType type, double amount,
      {bool excluded = false}) => FinanceEntry(
    id: id, type: type, amount: amount, date: DateTime(2026, 10, day),
    category: 'مطاعم', excluded: excluded,
  );

  test('monthly PDF includes excluded entries but not in totals', () {
    final report = MonthlyReportData(month: month, allEntries: [
      transaction(3, 'expense', EntryType.withdrawal, 50),
      transaction(2, 'income', EntryType.deposit, 200),
      transaction(4, 'excluded', EntryType.withdrawal, 300, excluded: true),
      FinanceEntry(id: 'old', type: EntryType.deposit, amount: 900,
          date: DateTime(2026, 9, 28), category: 'راتب'),
    ]);
    expect(report.entries.map((e) => e.id), ['income', 'expense', 'excluded']);
    expect(report.totals.deposit, 200);
    expect(report.totals.withdrawal, 50);
    expect(report.totals.remaining, 150);
    expect(report.filename, 'hesabaty-2026-10.pdf');
    expect(report.pageCount, 1);
  });

  test('empty month still has one page with zero totals', () {
    final report = MonthlyReportData(month: month, allEntries: []);
    expect(report.entries, isEmpty);
    expect(report.totals.transactionCount, 0);
    expect(report.pageCount, 1);
  });

  test('reports with more than 16 transactions span pages', () {
    final report = MonthlyReportData(month: month, allEntries: [
      for (var i = 0; i < 33; i++)
        transaction(1 + i % 25, '$i', EntryType.withdrawal, 1),
    ]);
    expect(report.pageCount, 3);
    expect(report.totals.withdrawal, 33);
  });
}
