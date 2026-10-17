import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/monthly_report.dart';

void main() {
  test('report amount header uses selected currency in both languages', () {
    expect(MonthlyReportCopy.amountHeader(true, 'USD'), 'Amount (USD)');
    expect(MonthlyReportCopy.amountHeader(false, 'AED'), 'المبلغ (AED)');
    expect(MonthlyReportCopy.totalWithCurrency(1250.5, 'EUR'),
        '1,250.5 EUR');
    expect(MonthlyReportCopy.amountHeader(true, 'INVALID'),
        'Amount (EGP)');
  });

  test('PDF title follows language selection', () {
    expect(MonthlyReportCopy.title(true), 'Monthly transaction report');
    expect(MonthlyReportCopy.title(false), 'تقرير المعاملات الشهري');
  });

  test('PDF uses English transaction types without changing amounts', () {
    expect(MonthlyReportCopy.entryType(true, EntryType.deposit), 'Income');
    expect(MonthlyReportCopy.entryType(true, EntryType.withdrawal), 'Expense');
    expect(MonthlyReportCopy.entryType(false, EntryType.deposit), 'إيداع');
  });
}
