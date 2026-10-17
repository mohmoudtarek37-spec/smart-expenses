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
    this.linkedInstallment = '',
    this.installmentCreated = false,
    this.originalMessage = '',
    this.receiptDataUrl = '',
    this.sender = '',
    this.fingerprint = '',
    this.createdAt = '',
    this.extraFields = const {},
  }) : assert(amount >= 0);

  final String id;
  final EntryType type;
  final double amount;
  final DateTime date;
  final String category;
  final String source;
  final String note;
  final bool excluded;
  final String linkedInstallment;
  final bool installmentCreated;
  /// Legacy backup details must be kept even while their editor is unfinished.
  final String originalMessage;
  final String receiptDataUrl;
  final String sender;
  final String fingerprint;
  final String createdAt;
  final Map<String, dynamic> extraFields;

  FinanceEntry copyWith({String? linkedInstallment, bool? installmentCreated}) => FinanceEntry(
    id: id, type: type, amount: amount, date: date, category: category,
    source: source, note: note, excluded: excluded,
    linkedInstallment: linkedInstallment ?? this.linkedInstallment,
    installmentCreated: installmentCreated ?? this.installmentCreated,
    originalMessage: originalMessage,
    receiptDataUrl: receiptDataUrl,
    sender: sender,
    fingerprint: fingerprint,
    createdAt: createdAt,
    extraFields: extraFields,
  );

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
      ...extraFields,
      'id': id,
      'type': type.name,
      'amount': amount,
      'date': [date.year.toString().padLeft(4, '0'),
               date.month.toString().padLeft(2, '0'),
               date.day.toString().padLeft(2, '0')].join('-'),
      'category': category,
      'source': source,
      'note': note,
      'excluded': excluded,
      'linkedInstallment': linkedInstallment,
      'installmentCreated': installmentCreated,
      'originalMessage': originalMessage,
      'receiptDataUrl': receiptDataUrl,
      'sender': sender,
      'fingerprint': fingerprint,
      'createdAt': createdAt,
    };
  }

  factory FinanceEntry.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final type = value['type'];
    final amount = value['amount'];
    final storedDate = value['date'];
    if (id is! String || id.isEmpty || type is! String ||
        !['deposit', 'withdrawal'].contains(type) || amount is! num ||
        !amount.toDouble().isFinite || amount < 0 ||
        storedDate is! String || storedDate.length != 10) {
      throw const FormatException('Invalid finance entry');
    }
    final date = DateTime.tryParse(storedDate);
    if (date == null ||
        [date.year.toString().padLeft(4, '0'),
         date.month.toString().padLeft(2, '0'),
         date.day.toString().padLeft(2, '0')].join('-') != storedDate) {
      throw const FormatException('Invalid transaction date');
    }
    String readText(String key) {
      final field = value[key];
      if (field == null) return '';
      if (field is! String) throw const FormatException('Invalid text field');
      return field;
    }
    if (value['linkedInstallment'] != null &&
        value['linkedInstallment'] is! String) {
      throw const FormatException('Invalid installment link');
    }
    if (value['installmentCreated'] != null &&
        value['installmentCreated'] is! bool) {
      throw const FormatException('Invalid installment-created flag');
    }
    if (value['excluded'] != null && value['excluded'] is! bool) {
      throw const FormatException('Invalid exclusion flag');
    }
    const known = {
      'id', 'type', 'amount', 'date', 'category', 'source', 'note',
      'excluded', 'linkedInstallment', 'installmentCreated',
      'originalMessage', 'receiptDataUrl', 'sender', 'fingerprint', 'createdAt'
    };
    final extra = Map<String, dynamic>.from(value)
      ..removeWhere((key, _) => known.contains(key));
    final receiptDataUrl = readText('receiptDataUrl');
    if (receiptDataUrl.isNotEmpty &&
        !RegExp(r'^data:image/(?:png|jpeg|webp);base64,', caseSensitive: false)
            .hasMatch(receiptDataUrl)) {
      throw const FormatException('Unsupported receipt image data');
    }
    return FinanceEntry(
      id: id,
      type: type == 'deposit' ? EntryType.deposit : EntryType.withdrawal,
      amount: amount.toDouble(),
      date: date,
      category: readText('category'),
      source: readText('source'),
      note: readText('note'),
      excluded: value['excluded'] == true,
      linkedInstallment: readText('linkedInstallment'),
      installmentCreated: value['installmentCreated'] == true,
      originalMessage: readText('originalMessage'),
      receiptDataUrl: readText('receiptDataUrl'),
      sender: readText('sender'),
      fingerprint: readText('fingerprint'),
      createdAt: readText('createdAt'),
      extraFields: extra,
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
