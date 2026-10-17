// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/sms_import.dart';

void main() {
  final day = DateTime(2026, 10, 17);
  test('imports JSON transaction and rejects OTP', () {
    final result = SmsImportParser.read(
      '[{"sender":"CIB","date":"2026-10-15",'
      '"body":"Purchase of EGP 850.00 at Carrefour"},'
      '{"sender":"CIB","date":"2026-10-15",'
      '"body":"OTP verification code 12345"}]', 'bank.json', today: day);
    expect(result.length, 2);
    expect(result.first.valid, isTrue);
    expect(result.first.amount, 850);
    expect(result.first.type, EntryType.withdrawal);
    expect(result.last.valid, isFalse);
    final transaction = result.first.toEntry('new-id');
    expect(transaction.originalMessage, contains('Carrefour'));
    expect(transaction.fingerprint, isNotEmpty);
  });

  test('handles Arabic digit currency and date from CSV', () {
    final result = SmsImportParser.read(
      'sender,date,body\nBank,2026-10-03,"تم إيداع ١٢٥٠ جنيه"\n',
      'messages.csv', today: day);
    expect(result, hasLength(1));
    expect(result.single.valid, isTrue);
    expect(result.single.type, EntryType.deposit);
    expect(result.single.amount, 1250);
    expect(result.single.date.day, 3);
  });

  test('reads TXT and ignores amounts without an explicit currency', () {
    final result = SmsImportParser.read(
      'تم خصم 500 من حسابك', 'messages.txt', today: day);
    expect(result.single.type, EntryType.withdrawal);
    expect(result.single.valid, isFalse);
  });

  test('ignores balance while choosing a purchase amount', () {
    final result = SmsImportParser.read(
      '[{"body":"Your balance is EGP 1000. '
      'Purchase of EGP 200 from account"}]',
      'messages.json', today: day);
    expect(result.single.type, EntryType.withdrawal);
    expect(result.single.amount, 200);
  });

  test('deduplicates repeated file imports including legacy messages', () {
    const message = 'Purchase of EGP 75 at store';
    final record = SmsImportParser.read(
      '[{"sender":"CIB","date":"2026-10-17","body":"'
      'Purchase of EGP 75 at store"}]',
      'messages.json', today: day).single;
    final existing = [
      FinanceEntry(id: 'old', type: EntryType.withdrawal, amount: 75,
        date: day, category: 'أخرى', sender: 'CIB',
        originalMessage: message, fingerprint: 'legacy-old-hash'),
    ];
    expect(SmsImportParser.alreadyImported(record, existing), isTrue);
  });

  test('rejects oversized batches and broken JSON without modifying data', () {
    expect(() => SmsImportParser.read('[]', 'x.json'),
        throwsFormatException);
    expect(() => SmsImportParser.read('{bad', 'x.json'),
        throwsFormatException);
    final many = '[' +
        List.filled(201, '{"body":"purchase EGP 3"}').join(',') + ']';
    expect(() => SmsImportParser.read(many, 'x.json'),
        throwsFormatException);
  });
}
