import 'finance_models.dart';

String encodeMonth(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-'
    '${month.month.toString().padLeft(2, '0')}';

DateTime parseMonth(String raw) {
  if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(raw)) {
    throw const FormatException('Invalid month format');
  }
  final month = DateTime.tryParse('$raw-01');
  if (month == null || encodeMonth(month) != raw) {
    throw const FormatException('Invalid calendar month');
  }
  return month;
}

DateTime parseCalendarDay(String raw) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    throw const FormatException('Invalid date format');
  }
  final day = DateTime.tryParse(raw);
  if (day == null ||
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}' != raw) {
    throw const FormatException('Invalid calendar date');
  }
  return day;
}

class InstallmentPayment {
  const InstallmentPayment({
    required this.month,
    required this.transactionId,
    required this.date,
  });

  final DateTime month;
  final String transactionId;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'month': encodeMonth(month),
    'txId': transactionId,
    'date': [
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ].join('-'),
  };

  factory InstallmentPayment.fromJson(Map<String, dynamic> value) {
    final month = value['month'];
    final transactionId = value['txId'];
    final date = value['date'];
    if (month is! String ||
        transactionId is! String || transactionId.isEmpty ||
        date is! String) {
      throw const FormatException('Invalid installment payment');
    }
    return InstallmentPayment(
      month: parseMonth(month),
      transactionId: transactionId,
      date: parseCalendarDay(date),
    );
  }
}

class InstallmentPlan {
  const InstallmentPlan({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueDay,
    required this.startMonth,
    required this.count,
    this.active = true,
    this.payments = const [],
  });

  final String id;
  final String name;
  final double amount;
  final int dueDay;
  final DateTime startMonth;
  /// 0 = recurring without end; positive = number of months from start.
  final int count;
  final bool active;
  final List<InstallmentPayment> payments;

  DateTime dueDate(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month,
        dueDay <= lastDay ? dueDay : lastDay);
  }

  bool appliesTo(DateTime month) {
    if (!active) return false;
    final offset = (month.year - startMonth.year) * 12 +
        month.month - startMonth.month;
    return offset >= 0 && (count == 0 || offset < count);
  }

  InstallmentPayment? paymentFor(DateTime month) {
    final key = encodeMonth(month);
    for (final payment in payments) {
      if (encodeMonth(payment.month) == key) return payment;
    }
    return null;
  }

  InstallmentPlan copyWith({
    String? name,
    double? amount,
    int? dueDay,
    DateTime? startMonth,
    int? count,
    bool? active,
    List<InstallmentPayment>? payments,
  }) => InstallmentPlan(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    dueDay: dueDay ?? this.dueDay,
    startMonth: startMonth ?? this.startMonth,
    count: count ?? this.count,
    active: active ?? this.active,
    payments: payments ?? this.payments,
  );

  void validate() {
    if (id.isEmpty || name.trim().isEmpty || name.length > 100 ||
        !amount.isFinite || amount <= 0 || dueDay < 1 || dueDay > 31 ||
        count < 0 || count > 240 ||
        encodeMonth(startMonth) !=
            encodeMonth(DateTime(startMonth.year, startMonth.month))) {
      throw const FormatException('Invalid installment plan');
    }
    final paidMonths = <String>{};
    for (final payment in payments) {
      final month = encodeMonth(payment.month);
      if (!paidMonths.add(month) || payment.transactionId.isEmpty ||
          !appliesTo(payment.month)) {
        throw const FormatException('Invalid or duplicate payment month');
      }
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'id': id, 'name': name, 'amount': amount, 'dueDay': dueDay,
      'startMonth': encodeMonth(startMonth), 'count': count,
      'active': active,
      'payments': payments.map((p) => p.toJson()).toList(),
    };
  }

  factory InstallmentPlan.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final name = value['name'];
    final amount = value['amount'];
    final dueDay = value['dueDay'];
    final startMonth = value['startMonth'];
    final count = value['count'];
    final active = value['active'];
    final rawPayments = value['payments'];
    if (id is! String || name is! String || amount is! num ||
        dueDay is! int || startMonth is! String || count is! int ||
        active is! bool || rawPayments is! List) {
      throw const FormatException('Invalid stored installment plan');
    }
    final payments = rawPayments.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored payment');
      }
      return InstallmentPayment.fromJson(item);
    }).toList();
    final result = InstallmentPlan(
      id: id, name: name, amount: amount.toDouble(), dueDay: dueDay,
      startMonth: parseMonth(startMonth), count: count,
      active: active, payments: payments,
    );
    result.validate();
    return result;
  }
}

enum DueStatus { paid, overdue, today, upcoming }

DueStatus statusFor(InstallmentPlan plan, DateTime month, DateTime today) {
  if (plan.paymentFor(month) != null) return DueStatus.paid;
  final due = plan.dueDate(month);
  final now = DateTime(today.year, today.month, today.day);
  if (due.isBefore(now)) return DueStatus.overdue;
  if (due == now) return DueStatus.today;
  return DueStatus.upcoming;
}

class InstallmentMonthSummary {
  InstallmentMonthSummary(List<InstallmentPlan> all, DateTime month)
      : plans = all.where((plan) => plan.appliesTo(month)).toList()
          ..sort((a, b) => a.dueDay.compareTo(b.dueDay)),
        month = DateTime(month.year, month.month, 1);

  final DateTime month;
  final List<InstallmentPlan> plans;

  double get total => plans.fold(0, (sum, plan) => sum + plan.amount);
  double get paid => plans.where((p) => p.paymentFor(month) != null)
      .fold(0, (sum, plan) => sum + plan.amount);
  double get remaining => total - paid;
}

/// Local atomic draft. Installment payments reference one withdrawal;
/// they NEVER charge the account automatically.
class InstallmentLedger {
  const InstallmentLedger({
    required this.entries,
    required this.installments,
    this.customCategories = const [],
    this.prefs = const {},
    this.createdAt = '',
  });

  final List<FinanceEntry> entries;
  final List<InstallmentPlan> installments;
  final List<String> customCategories;
  final Map<String, dynamic> prefs;
  final String createdAt;

  InstallmentLedger withCollections({
    required List<FinanceEntry> entries,
    required List<InstallmentPlan> installments,
  }) => InstallmentLedger(
    entries: entries,
    installments: installments,
    customCategories: customCategories,
    prefs: prefs,
    createdAt: createdAt,
  );

  InstallmentLedger withPlan(InstallmentPlan plan) {
    plan.validate();
    final updated = List<InstallmentPlan>.from(installments);
    final index = updated.indexWhere((item) => item.id == plan.id);
    if (index < 0) {
      updated.add(plan);
    } else {
      updated[index] = plan;
    }
    return withCollections(entries: entries, installments: updated);
  }

  /// Removing a plan does not delete paid withdrawal records. Detach the
  /// old references so those preserved transactions can be edited normally.
  InstallmentLedger withoutPlan(String id) => withCollections(
    entries: entries.map((entry) => entry.linkedInstallment == id
        ? entry.copyWith(linkedInstallment: '', installmentCreated: false)
        : entry).toList(),
    installments: installments.where((i) => i.id != id).toList(),
  );

  InstallmentLedger recordPayment({
    required String installmentId,
    required DateTime month,
    required DateTime paidOn,
    required String newTransactionId,
    String? existingTransactionId,
  }) {
    final index = installments.indexWhere((i) => i.id == installmentId);
    if (index < 0) throw StateError('Installment no longer exists');
    final plan = installments[index];
    if (!plan.appliesTo(month)) throw StateError('Plan inactive for month');
    if (plan.paymentFor(month) != null) {
      throw StateError('Installment already paid this month');
    }
    final updatedEntries = List<FinanceEntry>.from(entries);
    late final String txId;
    if (existingTransactionId != null) {
      final i = updatedEntries.indexWhere((entry) =>
          entry.id == existingTransactionId);
      if (i < 0) throw StateError('Existing withdrawal not found');
      final existing = updatedEntries[i];
      if (existing.type != EntryType.withdrawal || existing.excluded ||
          !FinanceSummary.sameMonth(existing.date, month) ||
          (existing.amount - plan.amount).abs() > 0.011 ||
          existing.linkedInstallment.isNotEmpty) {
        throw StateError('Withdrawal is not eligible for linking');
      }
      txId = existing.id;
      updatedEntries[i] = existing.copyWith(linkedInstallment: plan.id);
    } else {
      if (newTransactionId.isEmpty ||
          updatedEntries.any((e) => e.id == newTransactionId)) {
        throw StateError('New withdrawal ID is invalid or duplicate');
      }
      txId = newTransactionId;
      updatedEntries.add(FinanceEntry(
        id: txId, type: EntryType.withdrawal, amount: plan.amount,
        date: DateTime(paidOn.year, paidOn.month, paidOn.day),
        category: 'أقساط', source: 'قسط شهري', note: 'قسط ${plan.name}',
        linkedInstallment: plan.id, installmentCreated: true,
      ));
    }
    final payments = [...plan.payments,
      InstallmentPayment(month: month, transactionId: txId, date: paidOn)];
    final updatedPlans = List<InstallmentPlan>.from(installments);
    updatedPlans[index] = plan.copyWith(payments: payments);
    return withCollections(entries: updatedEntries, installments: updatedPlans);
  }

  InstallmentLedger undoPayment({
    required String installmentId, required DateTime month,
  }) {
    final index = installments.indexWhere((i) => i.id == installmentId);
    if (index < 0) throw StateError('Installment not found');
    final plan = installments[index];
    final payment = plan.paymentFor(month);
    if (payment == null) throw StateError('Installment not paid');
    final updatedPlans = List<InstallmentPlan>.from(installments);
    updatedPlans[index] = plan.copyWith(payments: plan.payments.where(
        (p) => encodeMonth(p.month) != encodeMonth(month)).toList());
    final updatedEntries = <FinanceEntry>[];
    for (final entry in entries) {
      if (entry.id != payment.transactionId) {
        updatedEntries.add(entry);
      } else if (!entry.installmentCreated) {
        updatedEntries.add(entry.copyWith(
          linkedInstallment: '', installmentCreated: false,
        ));
      }
    }
    return withCollections(entries: updatedEntries, installments: updatedPlans);
  }
}
