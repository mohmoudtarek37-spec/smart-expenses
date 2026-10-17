import 'installment_models.dart';

/// In-app reminders, with no READ_SMS, background service or exact alarm.
class DueNotice {
  const DueNotice({required this.plan, required this.due, required this.daysLeft});
  final InstallmentPlan plan;
  final DateTime due;
  final int daysLeft;
}

class InstallmentDueNotices {
  static List<DueNotice> upcoming(List<InstallmentPlan> plans, DateTime today,
      {int nextDays = 7}) {
    final todayDay = DateTime(today.year, today.month, today.day);
    final month = DateTime(today.year, today.month);
    final result = <DueNotice>[];
    for (final plan in plans) {
      if (!plan.appliesTo(month) || plan.paymentFor(month) != null) {
        continue;
      }
      final due = plan.dueDate(month);
      final days = due.difference(todayDay).inDays;
      if (days <= nextDays) {
        result.add(DueNotice(plan: plan, due: due, daysLeft: days));
      }
    }
    result.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return result;
  }
}
