import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../finance/finance_models.dart';
import '../finance/sms_import.dart';

/// A deliberate review step; nothing is saved until the user selects rows
/// and presses the final confirmation button.
class SmsImportReview extends StatefulWidget {
  const SmsImportReview({
    super.key, required this.records, required this.existing,
  });
  final List<SmsImportRecord> records;
  final List<FinanceEntry> existing;

  @override
  State<SmsImportReview> createState() => _SmsImportReviewState();
}

class _SmsImportReviewState extends State<SmsImportReview> {
  final Set<int> _selected = {};

  bool _eligible(int index) {
    final record = widget.records[index];
    if (!record.valid ||
        SmsImportParser.alreadyImported(record, widget.existing)) return false;
    for (var i = 0; i < index; i++) {
      if (widget.records[i].fingerprint == record.fingerprint) return false;
    }
    return true;
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اختار عملية صحيحة واحدة على الأقل للحفظ.'),
      ));
      return;
    }
    final count = _selected.length;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد استيراد الرسائل'),
        content: Text('هيتم إضافة ' + count.toString() +
            ' معاملة بعد مراجعتك إلى بيانات الجهاز. '
            'مفيش مزامنة تلقائية، ومش هنقرأ صندوق الرسائل. '
            'احتفظ بنسخة احتياطية قبل الاستيراد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: const Key('confirm-sms-save'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الحفظ'),
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
      appBar: AppBar(title: const Text('مراجعة رسائل SMS')),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('التحليل مبدئي فقط. راجع نوع ومبلغ وتاريخ كل رسالة. '
              'الرسائل غير المفهومة وأكواد التحقق والمكررة مش هتتحفظ. '
              'ممكن تعدّل المعاملة بعد الاستيراد.'),
        ),
        Expanded(child: ListView.builder(
          key: const Key('sms-review-list'),
          itemCount: widget.records.length,
          itemBuilder: (context, index) {
            final sms = widget.records[index];
            final eligible = _eligible(index);
            final dup = SmsImportParser.alreadyImported(sms, widget.existing) ||
                widget.records.take(index).any((r) => r.fingerprint == sms.fingerprint);
            final label = dup ? 'مكررة' : !sms.valid ? 'غير مؤكدة - تجاهل' :
                sms.type == EntryType.deposit ? 'إيداع' : 'سحب';
            final amount = sms.amount == null ? 'المبلغ غير معروف' :
                sms.amount!.toStringAsFixed(2) + ' جنيه';
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
            label: Text('حفظ ' + _selected.length.toString() + ' عملية مختارة'),
          ),
        ),
      ),
    );
  }
}
