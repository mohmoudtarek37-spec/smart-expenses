import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/installment_models.dart';
import 'package:hesabaty/finance/due_notices.dart';

void main() {
  final month = DateTime(2026, 10);
  InstallmentPlan plan(String id, int day, {bool active = true,
      List<InstallmentPayment> payments = const []}) => InstallmentPlan(
        id: id, name: id, amount: 300, dueDay: day,
        startMonth: month, count: 12, active: active, payments: payments);
  test('shows overdue, today, and next week in due-date order', () {
    final result = InstallmentDueNotices.upcoming([
      plan('far', 26), plan('late', 10),
      plan('today', 17), plan('soon', 24)
    ], DateTime(2026, 10, 17));
    expect(result.map((n) => n.plan.id), ['late', 'today', 'soon']);
    expect(result.map((n) => n.daysLeft), [-7, 0, 7]);
  });
  test('paid and inactive installment plans do not trigger reminders', () {
    final result = InstallmentDueNotices.upcoming([
      plan('paid', 17, payments: [
        InstallmentPayment(month: month, transactionId: 'tx',
            date: DateTime(2026, 10, 17))]),
      plan('inactive', 17, active: false),
    ], DateTime(2026, 10, 17));
    expect(result, isEmpty);
  });
  test('day 31 clamps to February 28', () {
    final result = InstallmentDueNotices.upcoming([
      InstallmentPlan(id: 'feb', name: 'rent', amount: 200, dueDay: 31,
        startMonth: DateTime(2026, 2), count: 1),
    ], DateTime(2026, 2, 23));
    expect(result.single.due.day, 28);
    expect(result.single.daysLeft, 5);
  });
}
