// ignore_for_file: prefer_interpolation_to_compose_strings
import 'installment_models.dart';

/// Generates a local iCalendar file. The user chooses if and where to import.
class InstallmentCalendar {
  static String export(List<InstallmentPlan> plans, DateTime today) {
    final output = <String>[
      'BEGIN:VCALENDAR', 'VERSION:2.0',
      'PRODID:-//Hesabaty//Installments//AR',
      'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
      'X-WR-CALNAME:أقساط حساباتي',
    ];
    var exported = 0;
    final now = DateTime(today.year, today.month, today.day);
    for (final plan in plans) {
      plan.validate();
      final totalMonths = plan.count == 0 ? 36 : plan.count;
      for (var i = 0; i < totalMonths && exported < 500; i++) {
        final month = DateTime(plan.startMonth.year, plan.startMonth.month + i);
        if (!plan.appliesTo(month)) continue;
        final due = plan.dueDate(month);
        if (due.isBefore(now)) continue;
        output.addAll([
          'BEGIN:VEVENT',
          'UID:' + plan.id + '-' + encodeMonth(month) + '@hesabaty-local',
          'DTSTAMP:' + _day(today.toUtc()) + 'T000000Z',
          'DTSTART;VALUE=DATE:' + _day(due),
          'DTEND;VALUE=DATE:' + _day(due.add(const Duration(days: 1))),
          'SUMMARY:' + _escape('قسط ' + plan.name + ' - ' +
              plan.amount.toStringAsFixed(2) + ' جنيه'),
          'DESCRIPTION:' + _escape('تذكير بقسط شهري. الدفع يدوي في حساباتي.'),
          'BEGIN:VALARM', 'ACTION:DISPLAY',
          'DESCRIPTION:' + _escape('موعد قسط ' + plan.name),
          'TRIGGER:-P1D', 'END:VALARM', 'END:VEVENT',
        ]);
        exported++;
      }
    }
    output.add('END:VCALENDAR');
    return output.join('\r\n') + '\r\n';
  }

  static String _escape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');

  static String _day(DateTime d) =>
      d.year.toString().padLeft(4, '0') +
      d.month.toString().padLeft(2, '0') +
      d.day.toString().padLeft(2, '0');
}
