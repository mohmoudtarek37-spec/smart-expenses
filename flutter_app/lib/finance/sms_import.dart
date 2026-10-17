// ignore_for_file: prefer_interpolation_to_compose_strings
// The normalized date and SMS fingerprint are concatenated deterministically.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'finance_models.dart';
import 'installment_models.dart';

/// Explicit, local-only SMS file import; never reads Android's SMS inbox.
class SmsImportRecord {
  const SmsImportRecord({
    required this.body, required this.sender, required this.date,
    required this.type, required this.amount, required this.fingerprint,
  });
  final String body;
  final String sender;
  final DateTime date;
  final EntryType? type;
  final double? amount;
  final String fingerprint;
  bool get valid => type != null && amount != null && amount! > 0;

  FinanceEntry toEntry(String id) => FinanceEntry(
    id: id, type: type!, amount: amount!, date: date,
    category: type == EntryType.deposit ? 'إيداع' : 'أخرى',
    source: sender.isEmpty ? 'SMS' : sender,
    note: sender.isEmpty ? 'عملية من SMS' : 'رسالة من ' + sender,
    originalMessage: body, sender: sender, fingerprint: fingerprint,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

class SmsImportParser {
  static const maxBytes = 3 * 1024 * 1024;
  static const maxRecords = 200;

  static List<SmsImportRecord> read(String text, String fileName, {DateTime? today}) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('SMS file is larger than 3 MB');
    }
    if (text.trim().isEmpty) throw const FormatException('Empty SMS file');
    final now = today ?? DateTime.now();
    final List<dynamic> input;
    if (fileName.toLowerCase().endsWith('.json')) {
      final decoded = jsonDecode(text);
      input = decoded is List ? decoded :
          decoded is Map && decoded['messages'] is List
              ? decoded['messages'] as List : [decoded];
    } else if (fileName.toLowerCase().endsWith('.csv')) {
      input = _csv(text);
    } else {
      input = text.trim().split(RegExp(r'\r?\n-{3,}\r?\n'));
    }
    if (input.isEmpty || input.length > maxRecords) {
      throw const FormatException('Import 1 to 200 SMS messages at a time');
    }
    return input.map((value) {
      final Map<dynamic, dynamic> item = value is Map ? value : {'body': value};
      String field(List<String> names) {
        for (final name in names) {
          final v = item[name];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return '';
      }
      final body = field(['body', 'message', 'text', 'الرسالة']);
      final sender = field(['sender', 'from', 'المرسل']);
      final dateText = field(['date', 'التاريخ']);
      DateTime date;
      try {
        date = dateText.isEmpty ? DateTime(now.year, now.month, now.day) :
          parseCalendarDay(dateText.substring(0, 10));
      } catch (_) {
        date = DateTime(now.year, now.month, now.day);
      }
      final content = _digits(body.toLowerCase());
      final isOtp = RegExp(r'\botp\b|verification code|security code|'
          r'(?:رمز|كود)\s*(?:التحقق|التأكيد|التاكيد)').hasMatch(content);
      final deposit = RegExp(r'credited|received|deposit|'
          r'إيداع|ايداع|استلام|تحويل\s+وارد').hasMatch(content);
      final withdrawal = RegExp(r'debited|withdrawn|withdrawal|purchase|'
          r'purchased|paid|payment|خصم|سحب|شراء|تحويل\s+صادر').hasMatch(content);
      final EntryType? type = isOtp || deposit == withdrawal ? null :
          deposit ? EntryType.deposit : EntryType.withdrawal;
      final amounts = RegExp(
        r'(\d[\d,. ]{0,19})\s*(?:egp\b|جنيه|ج\s*\.?\s*م\.?|l\.?e\.?)'
        r'|(?:egp\b|جنيه|ج\s*\.?\s*م\.?|l\.?e\.?)\s*(\d[\d,. ]{0,19})',
        caseSensitive: false,
      ).allMatches(content);
      double? amount;
      for (final match in amounts) {
        final raw = (match.group(1) ?? match.group(2) ?? '')
            .replaceAll(',', '').replaceAll(' ', '');
        final possible = double.tryParse(raw);
        if (possible == null || !possible.isFinite || possible <= 0 ||
            possible >= 1e12) {
          continue;
        }
        final prefix = content.substring(
            match.start > 23 ? match.start - 23 : 0, match.start);
        if (RegExp(r'balance|الرصيد|المتاح|available').hasMatch(prefix)) continue;
        amount = possible;
        break;
      }
      final day = date.year.toString().padLeft(4, '0') + '-' +
          date.month.toString().padLeft(2, '0') + '-' +
          date.day.toString().padLeft(2, '0');
      final normalizedBody = body.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final fingerprint = sha256.convert(utf8.encode(day + '|' +
          sender.toLowerCase() + '|' + normalizedBody)).toString();
      return SmsImportRecord(body: body, sender: sender, date: date,
          type: type, amount: isOtp ? null : amount, fingerprint: fingerprint);
    }).toList(growable: false);
  }

  static String _digits(String s) => s.replaceAllMapped(
      RegExp(r'[٠-٩]'), (m) =>
        '٠١٢٣٤٥٦٧٨٩'.indexOf(m.group(0)!).toString());

  static List<Map<String, String>> _csv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quote = false;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (quote) {
        if (ch == '"' && i + 1 < source.length && source[i + 1] == '"') {
          field.write('"'); i++;
        } else if (ch == '"') {
          quote = false;
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quote = true;
      } else if (ch == ',') {
        row.add(field.toString()); field = StringBuffer();
      } else if (ch == '\n') {
        row.add(field.toString().trim()); rows.add(row);
        row = []; field = StringBuffer();
      } else {
        field.write(ch);
      }
    }
    if (quote) throw const FormatException('Malformed CSV');
    row.add(field.toString().trim());
    if (row.any((e) => e.isNotEmpty)) rows.add(row);
    if (rows.length < 2) throw const FormatException('CSV has no messages');
    final headers = rows.first.map((s) => s.toLowerCase().trim()).toList();
    return rows.skip(1).map((values) => {
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < values.length ? values[i] : '',
    }).toList(growable: false);
  }

  static bool alreadyImported(SmsImportRecord sms, List<FinanceEntry> ledger) {
    final normalized = sms.body.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return ledger.any((entry) =>
      entry.fingerprint == sms.fingerprint ||
      (entry.originalMessage.isNotEmpty &&
       entry.originalMessage.replaceAll(RegExp(r'\s+'), ' ').toLowerCase() == normalized &&
       entry.sender.toLowerCase() == sms.sender.toLowerCase() &&
       entry.date.year == sms.date.year &&
       entry.date.month == sms.date.month &&
       entry.date.day == sms.date.day));
  }
}
