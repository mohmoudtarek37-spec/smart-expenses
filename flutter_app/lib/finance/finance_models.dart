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

  Map<String, dynamic> toJson() {
    if (id.isEmpty || !amount.isFinite || amount < 0) {
      throw const FormatException('Invalid finance entry');
    }
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'date': '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'category': category,
      'source': source,
      'note': note,
      'excluded': excluded,
    };
  }

  factory FinanceEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final typeValue = json['type'];
    final amountValue = json['amount'];
    final dateValue = json['date'];
    if (id is! String || id.isEmpty ||
        typeValue is! String || amountValue is! num ||
        dateValue is! String ||
        !RegExp(r'^\\d{4}-\\d{2}-\\d{2}

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
).hasMatch(dateValue)) {
      throw const FormatException('Invalid stored finance entry');
    }
    final date = DateTime.tryParse(dateValue);
    if (date == null ||
        '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}' != dateValue ||
        !amountValue.toDouble().isFinite || amountValue < 0 ||
        !['deposit', 'withdrawal'].contains(typeValue)) {
      throw const FormatException('Invalid stored finance data');
    }
    String textField(String key) {
      final value = json[key];
      if (value == null) return '';
      if (value is! String) {
        throw const FormatException('Invalid transaction text');
      }
      return value;
    }
    if (json['excluded'] != null && json['excluded'] is! bool) {
      throw const FormatException('Invalid transaction exclusion flag');
    }
    return FinanceEntry(
      id: id,
      type: typeValue == 'deposit' ? EntryType.deposit : EntryType.withdrawal,
      amount: amountValue.toDouble(),
      date: date,
      category: textField('category'),
      source: textField('source'),
      note: textField('note'),
      excluded: json['excluded'] == true,
    );
  }
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
