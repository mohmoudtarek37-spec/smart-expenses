import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/installment_models.dart';
import 'package:hesabaty/finance/installment_calendar.dart';

void main() {
  test('calendar clamps due day in February and exports reminders', () {
    final plan = InstallmentPlan(
      id: 'phone', name: 'موبايل', amount: 300, dueDay: 31,
      startMonth: DateTime(2027, 1), count: 3,
    );
    final calendar = InstallmentCalendar.export([plan], DateTime(2027, 1, 1));
    expect(calendar, contains('DTSTART;VALUE=DATE:20270228'));
    expect(calendar, contains('TRIGGER:-P1D'));
    expect('BEGIN:VEVENT'.allMatches(calendar).length, 3);
  });
  test('old plans do not add past events', () {
    final plan = InstallmentPlan(
      id: 'rent', name: 'إيجار', amount: 100, dueDay: 5,
      startMonth: DateTime(2025), count: 2,
    );
    final calendar = InstallmentCalendar.export([plan], DateTime(2026));
    expect(calendar, isNot(contains('BEGIN:VEVENT')));
  });
}
