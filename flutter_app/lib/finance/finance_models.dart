/// Domain rules ported from the HTML application's month and totals logic.
enum EntryType { deposit, withdrawal }

class FinanceEntry {
  const FinanceEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.source = '',
    this.note = '',
    this.excluded = false,
  }) : assert(amount >= 0);

  final String id;
  final EntryType type;
  final double amount;
  final DateTime date;
  final String category;
  final String source;
  final String note;
  final bool excluded;

  String get title => note.trim().isNotEmpty
      ? note.trim()
      : category.isNotEmpty
          ? category
          : type == EntryType.deposit ? 'إيداع' : 'سحب';
}

class MonthTotals {
  const MonthTotals({
    required this.deposit,
    required this.withdrawal,
    required this.transactionCount,
  });

  final double deposit;
  final double withdrawal;
  final int transactionCount;

  double get remaining => deposit - withdrawal;
  double get spendingPercentage =>
      deposit <= 0 ? 0 : withdrawal / deposit * 100;
  double get ringPercentage => spendingPercentage.clamp(0, 100).toDouble();
}

class FinanceSummary {
  const FinanceSummary(this.entries);

  final List<FinanceEntry> entries;

  static bool sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Exclusions affect calculations but not the transaction list, like HTML v1.
  List<FinanceEntry> monthEntries(DateTime month) => entries
      .where((entry) => sameMonth(entry.date, month))
      .toList(growable: false);

  MonthTotals totals(DateTime month) {
    var deposit = 0.0;
    var withdrawal = 0.0;
    var count = 0;
    for (final entry in monthEntries(month)) {
      if (entry.excluded) continue;
      count++;
      if (entry.type == EntryType.deposit) {
        deposit += entry.amount;
      } else {
        withdrawal += entry.amount;
      }
    }
    return MonthTotals(
      deposit: deposit,
      withdrawal: withdrawal,
      transactionCount: count,
    );
  }

  List<MapEntry<String, double>> categoryTotals(DateTime month) {
    final result = <String, double>{};
    for (final entry in monthEntries(month)) {
      if (entry.excluded || entry.type != EntryType.withdrawal) continue;
      final category = entry.category.isEmpty ? 'أخرى' : entry.category;
      result[category] = (result[category] ?? 0) + entry.amount;
    }
    return result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  List<FinanceEntry> recent(DateTime month, {int limit = 5}) {
    final entries = monthEntries(month).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return entries.take(limit).toList(growable: false);
  }
}

/// Advances in calendar months without depending on the day of the month.
DateTime shiftMonth(DateTime current, int steps) =>
    DateTime(current.year, current.month + steps, 1);

const arabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String monthTitle(DateTime date) =>
    '${arabicMonths[date.month - 1]} ${date.year}';

String formattedDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
