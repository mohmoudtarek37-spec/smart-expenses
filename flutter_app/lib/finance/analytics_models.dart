import 'finance_models.dart';

/// Presentation-ready financial analytics calculated with the same
/// inclusion/exclusion rules as the HTML v1.5 dashboard.
class AnalyticsMonth {
  const AnalyticsMonth({required this.month, required this.totals});

  final DateTime month;
  final MonthTotals totals;
}

enum ExpenseDirection { increased, decreased, unchanged, noComparison, noExpenses }

class ExpenseComparison {
  const ExpenseComparison({
    required this.current,
    required this.previous,
    required this.direction,
    required this.percentage,
    required this.isPartialMonth,
  });

  final MonthTotals current;
  final MonthTotals previous;
  final ExpenseDirection direction;
  /// Percentage change in expenditure relative to the previous month.
  /// Null when previous expenses are zero (percentage is undefined).
  final double? percentage;
  final bool isPartialMonth;

  String describeEnglish(String Function(num) formatNumber) {
    if (direction == ExpenseDirection.noExpenses) {
      return 'No expenses recorded in either month.';
    }
    if (direction == ExpenseDirection.noComparison) {
      return 'There were no expenses last month, so a percentage '
          'comparison is not available.';
    }
    final partial = isPartialMonth
        ? ' (Preliminary comparison: this month is still in progress.)'
        : '';
    if (direction == ExpenseDirection.unchanged) {
      return 'Expenses are unchanged from last month$partial';
    }
    final movement = direction == ExpenseDirection.increased
        ? 'higher' : 'lower';
    return 'Expenses are $movement than last month by '
        '${formatNumber(percentage!.abs())}%$partial';
  }

  String describe(String Function(num) formatNumber) {
    if (direction == ExpenseDirection.noExpenses) {
      return 'مفيش مصروفات مسجلة في الشهرين.';
    }
    if (direction == ExpenseDirection.noComparison) {
      return 'الشهر السابق لم يكن فيه مصروفات مسجلة، '
          'لذلك المقارنة المئوية غير متاحة.';
    }
    final change = percentage!.abs();
    final directionWord = switch (direction) {
      ExpenseDirection.increased => 'أعلى',
      ExpenseDirection.decreased => 'أقل',
      ExpenseDirection.unchanged => 'مساوية',
      _ => '',
    };
    final partial = isPartialMonth
        ? ' (مقارنة مبدئية لأن الشهر لسه ما خلصش)' : '';
    if (direction == ExpenseDirection.unchanged) {
      return 'مصروفات الشهر مساوية للشهر السابق$partial.';
    }
    return 'مصروفات الشهر $directionWord من الشهر السابق بـ '
        '${formatNumber(change)}%$partial.';
  }
}

class AnalyticsSummary {
  AnalyticsSummary({
    required FinanceSummary summary,
    required DateTime selectedMonth,
    required this.today,
  }) : _summary = summary,
       month = DateTime(selectedMonth.year, selectedMonth.month);

  final FinanceSummary _summary;
  final DateTime month;
  final DateTime today;

  MonthTotals get current => _summary.totals(month);
  MonthTotals get previous => _summary.totals(shiftMonth(month, -1));

  List<AnalyticsMonth> get lastSixMonths => List.generate(6, (index) {
    final m = shiftMonth(month, index - 5);
    return AnalyticsMonth(month: m, totals: _summary.totals(m));
  }, growable: false);

  double get maxChartValue {
    var value = 1.0;
    for (final item in lastSixMonths) {
      if (item.totals.deposit > value) value = item.totals.deposit;
      if (item.totals.withdrawal > value) value = item.totals.withdrawal;
    }
    return value;
  }

  List<MapEntry<String, double>> get categories =>
      _summary.categoryTotals(month);

  ExpenseComparison get comparison {
    final monthCurrent = current;
    final monthPrevious = previous;
    final expenses = monthCurrent.withdrawal;
    final prevExpenses = monthPrevious.withdrawal;
    if (prevExpenses <= 0) {
      return ExpenseComparison(
        current: monthCurrent,
        previous: monthPrevious,
        direction: expenses <= 0
            ? ExpenseDirection.noExpenses
            : ExpenseDirection.noComparison,
        percentage: null,
        isPartialMonth: FinanceSummary.sameMonth(month, today),
      );
    }
    final percentage = (expenses - prevExpenses) / prevExpenses * 100;
    return ExpenseComparison(
      current: monthCurrent,
      previous: monthPrevious,
      direction: percentage > 0
          ? ExpenseDirection.increased
          : percentage < 0
              ? ExpenseDirection.decreased
              : ExpenseDirection.unchanged,
      percentage: percentage,
      isPartialMonth: FinanceSummary.sameMonth(month, today),
    );
  }

  /// HTML reports show a dash when deposits are zero instead of division by 0.
  double? get spendingShare =>
      current.deposit > 0
          ? current.withdrawal / current.deposit * 100
          : null;
}
