import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'finance_models.dart';

/// One month of transactions. Excluded rows remain visible, but never alter
/// totals, matching report.js in the HTML version.
class MonthlyReportData {
  MonthlyReportData({required this.month, required List<FinanceEntry> allEntries})
      : entries = allEntries
            .where((entry) => FinanceSummary.sameMonth(entry.date, month))
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
          });

  static const rowsPerPage = 16;
  final DateTime month;
  final List<FinanceEntry> entries;

  MonthTotals get totals => FinanceSummary(entries).totals(month);
  int get pageCount => math.max(1, (entries.length + rowsPerPage - 1) ~/ rowsPerPage);
  String get filename => 'hesabaty-'
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}.pdf';
}

/// Builds A4 reports *offline*. Flutter paints each page so Arabic letter
/// shaping relies on the device's native text renderer, not missing PDF fonts.
/// Like the legacy HTML report, the PDF pages are image-backed (not searchable).
class MonthlyReportPdf {
  static const int _width = 1120;
  static const int _height = 1584;

  static Future<Uint8List> create(MonthlyReportData report) async {
    final document = pw.Document(compress: true);
    for (var page = 0; page < report.pageCount; page++) {
      final png = await _paintPage(report, page);
      final image = pw.MemoryImage(png);
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
    }
    return document.save();
  }

  static Future<Uint8List> _paintPage(MonthlyReportData report, int page) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    void rectangle(double x, double y, double w, double h, Color color) {
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()..color = color,
      );
    }
    void text(
      String value,
      double x,
      double y,
      double width, {
      double size = 23,
      bool bold = false,
      Color color = const Color(0xFF172334),
      bool right = true,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color,
            height: 1.2,
          ),
        ),
        textDirection: right ? TextDirection.rtl : TextDirection.ltr,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width);
      painter.paint(canvas, Offset(x, y));
      painter.dispose();
    }

    const dark = Color(0xFF172334);
    const muted = Color(0xFF68798A);
    const green = Color(0xFF047857);
    const red = Color(0xFFB42340);
    final fmt = NumberFormat.decimalPattern('en')..maximumFractionDigits = 2;
    String amount(num value) => fmt.format(value);

    rectangle(0, 0, _width.toDouble(), _height.toDouble(), Colors.white);
    rectangle(0, 0, _width.toDouble(), 270, const Color(0xFFFAFBFE));
    rectangle(65, 269, 990, 2, const Color(0xFFD9E0E9));
    text('تقرير المعاملات الشهري', 65, 66, 990, size: 43, bold: true, color: dark);
    text(monthTitle(report.month), 65, 137, 990, size: 31, bold: true);
    text('حساباتي | تقرير محفوظ على جهازك', 65, 203, 990, size: 20, color: muted);
    text('صفحة ${page + 1} / ${report.pageCount}', 65, 204, 310,
        size: 18, right: false, color: muted);

    rectangle(65, 294, 990, 62, const Color(0xFFEDF1F6));
    text('التاريخ', 850, 309, 185, bold: true);
    text('النوع', 670, 309, 140, bold: true);
    text('المكان أو الوصف', 306, 309, 315, bold: true);
    text('المبلغ (جنيه)', 70, 309, 205, bold: true);

    final start = page * MonthlyReportData.rowsPerPage;
    final end = math.min(report.entries.length, start + MonthlyReportData.rowsPerPage);
    if (start == end) {
      text('لا توجد معاملات مسجلة لهذا الشهر', 65, 421, 990,
          size: 29, color: muted);
    }
    for (var i = start; i < end; i++) {
      final entry = report.entries[i];
      final row = i - start;
      final y = 395.0 + row * 63;
      if (row.isEven) {
        rectangle(65, y - 9, 990, 57, const Color(0xFFF7F9FC));
      }
      final deposit = entry.type == EntryType.deposit;
      final description = entry.title +
          (entry.excluded ? ' (مستبعدة)' : '');
      text(formattedDate(entry.date), 850, y, 185, size: 21);
      text(deposit ? 'إيداع' : 'سحب', 670, y, 140,
          size: 21, bold: true, color: deposit ? green : red);
      text(description, 306, y, 315, size: 20, color: dark);
      text((deposit ? '+' : '−') + amount(entry.amount), 70, y, 205,
          size: 21, right: false, bold: true, color: deposit ? green : red);
    }

    if (page == report.pageCount - 1) {
      rectangle(65, 1414, 990, 124, const Color(0xFFEDF1F6));
      text('إجمالي الإيداعات  ${amount(report.totals.deposit)}', 580, 1435,
          450, size: 23, bold: true, color: green);
      text('إجمالي السحب  ${amount(report.totals.withdrawal)}', 580, 1485,
          450, size: 23, bold: true, color: red);
      text('المتبقي  ${amount(report.totals.remaining)}', 75, 1460,
          465, size: 24, bold: true, right: false, color: dark);
    }
    text('أُعد محليًا | عدد العمليات: ${report.entries.length}',
        65, 1553, 990, size: 18, color: muted);

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(_width, _height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not encode PDF page');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}
