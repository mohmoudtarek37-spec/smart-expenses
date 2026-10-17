import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  InstallmentPlan makePlan({int dueDay = 31, int count = 12}) =>
      InstallmentPlan(
        id: 'phone', name: 'قسط الموبايل', amount: 1200,
        dueDay: dueDay, startMonth: DateTime(2026, 1), count: count,
      );

  test('day 31 is clamped to last day including leap-year February', () {
    final plan = makePlan();
    expect(plan.dueDate(DateTime(2026, 2)), DateTime(2026, 2, 28));
    expect(plan.dueDate(DateTime(2028, 2)), DateTime(2028, 2, 29));
    expect(plan.dueDate(DateTime(2026, 4)), DateTime(2026, 4, 30));
  });

  test('plan active for correct months and not before/after its term', () {
    final plan = makePlan();
    expect(plan.appliesTo(DateTime(2025, 12)), isFalse);
    expect(plan.appliesTo(DateTime(2026, 1)), isTrue);
    expect(plan.appliesTo(DateTime(2026, 12)), isTrue);
    expect(plan.appliesTo(DateTime(2027, 1)), isFalse);
    final ongoing = makePlan(count: 0);
    expect(ongoing.appliesTo(DateTime(2036, 2)), isTrue);
  });

  test('monthly summary and due states follow existing HTML rules', () {
    final plan = makePlan(dueDay: 15);
    final summary = InstallmentMonthSummary([plan], DateTime(2026, 4));
    expect(summary.total, 1200);
    expect(summary.paid, 0);
    expect(summary.remaining, 1200);
    expect(statusFor(plan, DateTime(2026, 4), DateTime(2026, 4, 14)),
        DueStatus.upcoming);
    expect(statusFor(plan, DateTime(2026, 4), DateTime(2026, 4, 15)),
        DueStatus.today);
    expect(statusFor(plan, DateTime(2026, 4), DateTime(2026, 4, 16)),
        DueStatus.overdue);
  });

  test('paying a month creates exactly one linked withdrawal', () {
    final ledger = InstallmentLedger(entries: const [],
        installments: [makePlan()]);
    final paid = ledger.recordPayment(
      installmentId: 'phone', month: DateTime(2026, 4),
      paidOn: DateTime(2026, 4, 15), newTransactionId: 'new-tx',
    );
    expect(paid.entries, hasLength(1));
    expect(paid.entries.single.amount, 1200);
    expect(paid.entries.single.linkedInstallment, 'phone');
    expect(paid.entries.single.installmentCreated, isTrue);
    expect(paid.installments.single.paymentFor(DateTime(2026, 4))!
        .transactionId, 'new-tx');
    expect(InstallmentMonthSummary(
        paid.installments, DateTime(2026, 4)).remaining, 0);
    expect(
      () => paid.recordPayment(
        installmentId: 'phone', month: DateTime(2026, 4),
        paidOn: DateTime(2026, 4, 16), newTransactionId: 'another',
      ), throwsStateError);
  });

  test('matching bank withdrawal can be linked without creating duplicates', () {
    final bankTx = FinanceEntry(
      id: 'bank-withdrawal', type: EntryType.withdrawal,
      amount: 1200, date: DateTime(2026, 4, 16),
      category: 'فواتير', source: 'CIB',
    );
    final ledger = InstallmentLedger(
        entries: [bankTx], installments: [makePlan()]);
    final paid = ledger.recordPayment(
        installmentId: 'phone', month: DateTime(2026, 4),
        paidOn: DateTime(2026, 4, 16), newTransactionId: 'not-used',
        existingTransactionId: bankTx.id);
    expect(paid.entries, hasLength(1));
    expect(paid.entries.single.linkedInstallment, 'phone');
    expect(paid.entries.single.installmentCreated, isFalse);
    final undone = paid.undoPayment(
        installmentId: 'phone', month: DateTime(2026, 4));
    expect(undone.entries, hasLength(1));
    expect(undone.entries.single.id, bankTx.id);
    expect(undone.entries.single.linkedInstallment, isEmpty);
    expect(undone.installments.single.payments, isEmpty);
  });

  test('undo deletes only withdrawal auto-created for payment', () {
    final ledger = InstallmentLedger(entries: const [],
        installments: [makePlan()]);
    final paid = ledger.recordPayment(
      installmentId: 'phone', month: DateTime(2026, 4),
      paidOn: DateTime(2026, 4, 15), newTransactionId: 'new-tx',
    );
    final undone = paid.undoPayment(
      installmentId: 'phone', month: DateTime(2026, 4));
    expect(undone.entries, isEmpty);
    expect(undone.installments.single.payments, isEmpty);
  });

  test('deleting a plan keeps past withdrawals and releases their links', () {
    final paid = InstallmentLedger(
        entries: const [], installments: [makePlan()]).recordPayment(
      installmentId: 'phone', month: DateTime(2026, 4),
      paidOn: DateTime(2026, 4, 15), newTransactionId: 'old-payment',
    );
    final after = paid.withoutPlan('phone');
    expect(after.installments, isEmpty);
    expect(after.entries, hasLength(1));
    expect(after.entries.single.amount, 1200);
    expect(after.entries.single.linkedInstallment, isEmpty);
    expect(after.entries.single.installmentCreated, isFalse);
  });

  test('invalid repeated payments and bad due days are rejected', () {
    final payment = InstallmentPayment(
      month: DateTime(2026, 4),
      transactionId: 'one', date: DateTime(2026, 4, 15),
    );
    final duplicate = makePlan().copyWith(payments: [payment, payment]);
    expect(duplicate.validate, throwsFormatException);
    expect(() => makePlan(dueDay: 32).validate(), throwsFormatException);
  });

  test('plan and payment survive a JSON roundtrip', () {
    final ledger = InstallmentLedger(entries: const [],
        installments: [makePlan()]);
    final paid = ledger.recordPayment(
      installmentId: 'phone', month: DateTime(2026, 4),
      paidOn: DateTime(2026, 4, 15), newTransactionId: 'new-tx',
    );
    final restored = InstallmentPlan.fromJson(
        paid.installments.single.toJson());
    expect(restored.name, 'قسط الموبايل');
    expect(restored.paymentFor(DateTime(2026, 4))?.transactionId, 'new-tx');
  });
}
