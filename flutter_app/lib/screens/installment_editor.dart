import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../finance/installment_models.dart';

enum InstallmentEditAction { save, delete }

class InstallmentEditResult {
  const InstallmentEditResult.save(this.plan)
      : action = InstallmentEditAction.save;
  const InstallmentEditResult.delete()
      : action = InstallmentEditAction.delete, plan = null;

  final InstallmentEditAction action;
  final InstallmentPlan? plan;
}

class InstallmentEditor extends StatefulWidget {
  const InstallmentEditor({super.key, this.original, required this.month,
      this.isEnglish = false});

  final InstallmentPlan? original;
  final DateTime month;
  final bool isEnglish;

  @override
  State<InstallmentEditor> createState() => _InstallmentEditorState();
}

class _InstallmentEditorState extends State<InstallmentEditor> {
  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _count;
  late DateTime _startMonth;
  late int _dueDay;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _name = TextEditingController(text: original?.name ?? '');
    _amount = TextEditingController(
        text: original == null ? '' : original.amount.toStringAsFixed(2));
    _count = TextEditingController(text: '${original?.count ?? 0}');
    _dueDay = original?.dueDay ?? DateTime.now().day;
    _startMonth = original?.startMonth ??
        DateTime(widget.month.year, widget.month.month);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _selectStartMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(_startMonth.year, _startMonth.month, 1),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _startMonth = DateTime(date.year, date.month));
    }
  }

  void _save() {
    if (!(_key.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amount.text.replaceAll(',', ''));
    final rounded = (amount * 100).round() / 100;
    final plan = InstallmentPlan(
      id: widget.original?.id ?? const Uuid().v4(),
      name: _name.text.trim(), amount: rounded,
      dueDay: _dueDay, startMonth: _startMonth,
      count: int.parse(_count.text),
      payments: widget.original?.payments ?? const [],
      active: widget.original?.active ?? true,
    );
    try {
      plan.validate();
      Navigator.of(context).pop(InstallmentEditResult.save(plan));
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('راجع تاريخ القسط وعدد الأشهر والدفعات المسجلة.'),
      ));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('حذف القسط؟', 'Delete installment?')),
        content: Text(_tr('معاملات السحب اللي اتسجلت وقت دفع القسط هتفضل موجودة '
          'ومش هتتمسح من سجل المصروفات.',
          'Transactions associated with this installment will remain in your expenses.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('إلغاء', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('حذف القسط', 'Delete installment')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const InstallmentEditResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20,
          MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.original == null
                  ? _tr('إضافة قسط جديد', 'Add installment')
                  : _tr('تعديل القسط', 'Edit installment'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('installment-name'),
                controller: _name, maxLength: 100,
                decoration: InputDecoration(
                  labelText: _tr('اسم القسط', 'Installment name'),
                  hintText: _tr('مثلاً: قسط الموبايل', 'e.g. Phone installment'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? _tr('اكتب اسم القسط', 'Enter installment name') : null,
              ),
              TextFormField(
                key: const Key('installment-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))
                ],
                decoration: InputDecoration(
                  labelText: _tr('القيمة الشهرية بالجنيه', 'Monthly amount (EGP)'),
                  border: const OutlineInputBorder(),
                ),
                validator: (raw) {
                  final input = (raw ?? '').replaceAll(',', '');
                  if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(input)) {
                    return _tr('اكتب قيمة صحيحة حتى رقمين عشريين',
                        'Enter an amount with up to two decimal places');
                  }
                  final value = double.tryParse(input);
                  return value == null || value <= 0 ? _tr('المبلغ أكبر من صفر', 'Amount must be positive') : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('installment-due-day'),
                initialValue: _dueDay,
                decoration: InputDecoration(
                  labelText: _tr('يوم الدفع', 'Payment due day'),
                  border: const OutlineInputBorder()),
                items: List.generate(31, (i) => DropdownMenuItem(
                  value: i + 1, child: Text('${_tr('يوم', 'Day')} ${i + 1}'),
                )),
                onChanged: (day) {
                  if (day != null) setState(() => _dueDay = day);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _selectStartMonth,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('${_tr('بداية القسط:', 'Starts:')} ${encodeMonth(_startMonth)}'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('installment-count'),
                controller: _count,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _tr('عدد الأشهر (0 يعني مستمر)', 'Months (0 for ongoing)'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final count = int.tryParse(v ?? '');
                  return count == null || count < 0 || count > 240
                      ? _tr('اختار من 0 لـ240 شهر', 'Choose 0–240 months') : null;
                },
              ),
              const SizedBox(height: 12),
              Text(_tr('يوم 31 في شهر قصير بيتحسب آخر يوم فيه. '
                  'القسط مش بيتخصم إلا لما تسجل الدفع يدويًا.',
                  'Due dates after the month end are moved to its last day. '
                  'Payments are recorded only when you confirm them.'),
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('save-installment'),
                onPressed: _save,
                child: Text(_tr('حفظ القسط', 'Save installment')),
              ),
              if (widget.original != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('delete-installment'),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_tr('حذف القسط', 'Delete installment')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
