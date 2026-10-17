// ignore_for_file: prefer_interpolation_to_compose_strings
// Review labels combine localized status, amount and full SMS preview text.
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../finance/finance_models.dart';
import '../finance/sms_import.dart';

/// A deliberate review step; nothing is saved until the user selects rows
/// and presses the final confirmation button.
class SmsImportReview extends StatefulWidget {
  const SmsImportReview({
    super.key, required this.records, required this.existing,
    this.isEnglish = false,
  });
  final List<SmsImportRecord> records;
  final List<FinanceEntry> existing;
  final bool isEnglish;

  @override
  State<SmsImportReview> createState() => _SmsImportReviewState();
}

class _SmsImportReviewState extends State<SmsImportReview> {
  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  final Set<int> _selected = {};

  bool _eligible(int index) {
    final record = widget.records[index];
    if (!record.valid ||
        SmsImportParser.alreadyImported(record, widget.existing)) {
      return false;
    }
    for (var i = 0; i < index; i++) {
      if (widget.records[i].fingerprint == record.fingerprint) return false;
    }
    return true;
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('اختار عملية صحيحة واحدة على الأقل للحفظ.',
            'Select at least one valid transaction.')),
      ));
      return;
    }
    final count = _selected.length;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('تأكيد استيراد الرسائل', 'Confirm SMS import')),
        content: Text(widget.isEnglish
            ? 'Import $count reviewed transactions on this device. '
              'Your SMS inbox will not be read. Keep a backup.'
            : 'هيتم إضافة $count معاملة بعد مراجعتك إلى بيانات الجهاز. '
              'مش هنقرأ صندوق الرسائل. احتفظ بنسخة احتياطية قبل الاستيراد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('رجوع', 'Back')),
          ),
          FilledButton(
            key: const Key('confirm-sms-save'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('تأكيد الحفظ', 'Confirm save')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final selected = _selected.toList()..sort();
    final entries = selected.map((index) =>
        widget.records[index].toEntry(const Uuid().v4())).toList(growable: false);
    Navigator.pop(context, entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tr('مراجعة رسائل SMS', 'Review SMS messages'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_tr('التحليل مبدئي فقط. راجع نوع ومبلغ وتاريخ كل رسالة. '
              'الرسائل غير المفهومة وأكواد التحقق والمكررة مش هتتحفظ. '
              'ممكن تعدّل المعاملة بعد الاستيراد.',
              'SMS detection is approximate. Review each amount and date. '
              'Unclear, duplicate and verification-code messages are excluded. '
              'You can edit transactions after import.')),
        ),
        Expanded(child: ListView.builder(
          key: const Key('sms-review-list'),
          itemCount: widget.records.length,
          itemBuilder: (context, index) {
            final sms = widget.records[index];
            final eligible = _eligible(index);
            final dup = SmsImportParser.alreadyImported(sms, widget.existing) ||
                widget.records.take(index).any((r) => r.fingerprint == sms.fingerprint);
            final label = dup ? _tr('مكررة', 'Duplicate')
                : !sms.valid ? _tr('غير مؤكدة - تجاهل', 'Unclear - skip') :
                sms.type == EntryType.deposit ? _tr('إيداع', 'Income')
                : _tr('سحب', 'Expense');
            final amount = sms.amount == null
                ? _tr('المبلغ غير معروف', 'Unknown amount') :
                sms.amount!.toStringAsFixed(2) + _tr(' جنيه', ' EGP');
            return CheckboxListTile(
              key: Key('sms-row-' + index.toString()),
              value: _selected.contains(index),
              onChanged: eligible ? (checked) {
                setState(() {
                  if (checked == true) {
                    _selected.add(index);
                  } else {
                    _selected.remove(index);
                  }
                });
              } : null,
              isThreeLine: true,
              title: Text(label + ' • ' + amount),
              subtitle: Text((sms.sender.isEmpty ? 'SMS' : sms.sender) + ' • ' +
                  formattedDate(sms.date) + '\n' +
                  (sms.body.length > 160
                      ? sms.body.substring(0, 160) + '…' : sms.body)),
            );
          },
        )),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('save-selected-sms'),
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: Text(_tr('حفظ ', 'Save ') + _selected.length.toString() +
                _tr(' عملية مختارة', ' selected transactions')),
          ),
        ),
      ),
    );
  }
}
