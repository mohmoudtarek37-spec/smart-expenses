import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../finance/finance_models.dart';

enum TransactionEditAction { save, delete }

class TransactionEditResult {
  const TransactionEditResult.save(this.entry) : action = TransactionEditAction.save;
  const TransactionEditResult.delete()
      : action = TransactionEditAction.delete, entry = null;

  final TransactionEditAction action;
  final FinanceEntry? entry;
}

class TransactionEditor extends StatefulWidget {
  const TransactionEditor({super.key, this.original});

  final FinanceEntry? original;

  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  static const _expenseCategories = <String>[
    'مشتريات', 'مصاريف شحن', 'اشتراكات', 'كهرباء', 'مياه',
    'مستلزمات بيت', 'مصاريف شخصية', 'أقساط', 'مطاعم', 'صحة',
    'مواصلات', 'فواتير', 'أخرى',
  ];
  static const _incomeCategories = <String>['راتب', 'تحويل وارد', 'إيداع', 'أخرى'];
  static const _sources = <String>[
    'CIB', 'البنك الأهلي', 'بنك مصر', 'InstaPay', 'Vodafone Cash',
    'Orange Cash', 'Etisalat Cash', 'WE Pay', 'نقدي', 'مصدر آخر',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late EntryType _type;
  late DateTime _date;
  late String _category;
  late String _source;
  late bool _excluded;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _type = original?.type ?? EntryType.withdrawal;
    _date = original?.date ?? DateTime.now();
    _category = original?.category ??
        (_type == EntryType.withdrawal ? 'مشتريات' : 'إيداع');
    _source = original?.source ?? 'نقدي';
    _excluded = original?.excluded ?? false;
    _amount = TextEditingController(
      text: original == null ? '' : original.amount.toStringAsFixed(2),
    );
    _note = TextEditingController(text: original?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final all = _type == EntryType.withdrawal
        ? _expenseCategories : _incomeCategories;
    return {...all, _category}.toList();
  }

  String? _validateAmount(String? raw) {
    final numberText = (raw ?? '').replaceAll(',', '').trim();
    if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(numberText)) {
      return 'اكتب مبلغًا صحيحًا أكبر من صفر، بحد أقصى رقمين بعد العلامة.';
    }
    final value = double.tryParse(numberText);
    if (value == null || !value.isFinite || value <= 0) {
      return 'المبلغ لازم يكون أكبر من صفر.';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosen != null && mounted) setState(() => _date = chosen);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final value = double.parse(_amount.text.replaceAll(',', '').trim());
    // Money is intentionally rounded to two decimals before saving.
    final amount = (value * 100).round() / 100;
    final entry = FinanceEntry(
      id: widget.original?.id ?? const Uuid().v4(),
      type: _type,
      amount: amount,
      date: DateTime(_date.year, _date.month, _date.day),
      category: _category,
      source: _source,
      note: _note.text.trim(),
      excluded: _excluded,
    );
    Navigator.of(context).pop(TransactionEditResult.save(entry));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المعاملة؟'),
        content: const Text('هيتم حذف المعاملة من بيانات النسخة التجريبية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const TransactionEditResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12, bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.original == null ? 'إضافة معاملة جديدة' : 'تعديل المعاملة',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                SegmentedButton<EntryType>(
                  segments: const [
                    ButtonSegment(value: EntryType.withdrawal, label: Text('سحب'),
                        icon: Icon(Icons.north_east)),
                    ButtonSegment(value: EntryType.deposit, label: Text('إيداع'),
                        icon: Icon(Icons.south_west)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selected) => setState(() {
                    _type = selected.first;
                    _category = _type == EntryType.deposit ? 'إيداع' : 'مشتريات';
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('transaction-amount'),
                  controller: _amount,
                  autofocus: widget.original == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  decoration: const InputDecoration(
                    labelText: 'المبلغ بالجنيه',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('transaction-category_${_type.name}'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'التصنيف', border: OutlineInputBorder()),
                  items: _categories.map((category) => DropdownMenuItem(
                    value: category, child: Text(category),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المصدر', border: OutlineInputBorder()),
                  items: {..._sources, if (_source.isNotEmpty) _source}
                      .map((source) => DropdownMenuItem(
                            value: source, child: Text(source),
                          )).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _source = value);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('التاريخ: ${formattedDate(_date)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLength: 250,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _excluded,
                  title: const Text('استبعاد من إجمالي الشهر'),
                  onChanged: (value) => setState(() => _excluded = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('save-transaction'),
                  onPressed: _save,
                  child: const Text('حفظ المعاملة'),
                ),
                if (widget.original != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('delete-transaction'),
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(foregroundColor: current.error),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف المعاملة'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
