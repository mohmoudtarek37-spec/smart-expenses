// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
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
  const TransactionEditor({super.key, this.original,
      this.customCategories = const [], this.isEnglish = false});

  final FinanceEntry? original;
  final List<String> customCategories;
  final bool isEnglish;

  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  String _categoryDisplay(String value) {
    if (!widget.isEnglish) return value;
    const names = <String, String>{
      'مشتريات': 'Shopping', 'مصاريف شحن': 'Shipping fees',
      'اشتراكات': 'Subscriptions', 'كهرباء': 'Electricity',
      'مياه': 'Water', 'مستلزمات بيت': 'Household',
      'مصاريف شخصية': 'Personal', 'أقساط': 'Installments',
      'مطاعم': 'Restaurants', 'صحة': 'Health',
      'مواصلات': 'Transport', 'فواتير': 'Bills',
      'أخرى': 'Other', 'راتب': 'Salary',
      'تحويل وارد': 'Incoming transfer', 'إيداع': 'Deposit',
    };
    return names[value] ?? value;
  }

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
  late String _receiptDataUrl;

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
    _receiptDataUrl = original?.receiptDataUrl ?? '';
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
    return {...all, ...widget.customCategories, _category}.toList();
  }

  String? _validateAmount(String? raw) {
    final numberText = (raw ?? '').replaceAll(',', '').trim();
    if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(numberText)) {
      return _tr('اكتب مبلغًا صحيحًا أكبر من صفر، بحد أقصى رقمين بعد العلامة.',
          'Enter a valid amount with no more than two decimal places.');
    }
    final value = double.tryParse(numberText);
    if (value == null || !value.isFinite || value <= 0) {
      return _tr('المبلغ لازم يكون أكبر من صفر.', 'Amount must be greater than zero.');
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

  Future<void> _chooseReceipt() async {
    try {
      final selected = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'صورة إيصال',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp']),
      ]);
      if (selected == null || !mounted) return;
      final data = await selected.readAsBytes();
      if (!mounted) return;
      if (data.isEmpty || data.length > 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('حجم صورة الإيصال لازم يكون أقل من 1 ميجابايت. '
              'صغّرها قبل اختيارها.'),
        ));
        return;
      }
      String? mime;
      if (data.length >= 4 && data[0] == 0x89 &&
          data[1] == 0x50 && data[2] == 0x4e && data[3] == 0x47) {
        mime = 'image/png';
      } else if (data.length >= 3 && data[0] == 0xff &&
          data[1] == 0xd8 && data[2] == 0xff) {
        mime = 'image/jpeg';
      } else if (data.length >= 12 &&
          String.fromCharCodes(data.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(data.sublist(8, 12)) == 'WEBP') {
        mime = 'image/webp';
      }
      if (mime == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('صيغة الصورة غير مدعومة. اختار PNG أو JPG أو WebP.'),
        ));
        return;
      }
      setState(() => _receiptDataUrl = 'data:' + mime! + ';base64,' + base64Encode(data));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر قراءة صورة الإيصال. البيانات القديمة لم تتغير.'),
      ));
    }
  }

  Widget _receiptPreview() {
    if (_receiptDataUrl.isEmpty) return const SizedBox.shrink();
    try {
      final bytes = Uint8List.fromList(base64Decode(_receiptDataUrl.split(',').last));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, height: 155, fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Text('تعذر عرض الصورة')),
        ),
      );
    } catch (_) {
      return const Text('تعذر عرض الصورة القديمة');
    }
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
      originalMessage: widget.original?.originalMessage ?? '',
      receiptDataUrl: _receiptDataUrl,
      sender: widget.original?.sender ?? '',
      fingerprint: widget.original?.fingerprint ?? '',
      createdAt: widget.original?.createdAt ?? '',
      extraFields: widget.original?.extraFields ?? const {},
    );
    Navigator.of(context).pop(TransactionEditResult.save(entry));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('حذف المعاملة؟', 'Delete transaction?')),
        content: Text(_tr('هيتم حذف المعاملة من بيانات النسخة التجريبية.',
          'This transaction will be deleted from local records.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('إلغاء', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('تأكيد الحذف', 'Delete')),
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
                Text(widget.original == null
                    ? _tr('إضافة معاملة جديدة', 'Add a transaction')
                    : _tr('تعديل المعاملة', 'Edit transaction'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                SegmentedButton<EntryType>(
                  segments: [
                    ButtonSegment(value: EntryType.withdrawal,
                        label: Text(_tr('سحب', 'Expense')),
                        icon: const Icon(Icons.north_east)),
                    ButtonSegment(value: EntryType.deposit,
                        label: Text(_tr('إيداع', 'Income')),
                        icon: const Icon(Icons.south_west)),
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
                  decoration: InputDecoration(
                    labelText: _tr('المبلغ بالجنيه', 'Amount (EGP)'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('transaction-category_${_type.name}'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _tr('التصنيف', 'Category'),
                    border: const OutlineInputBorder()),
                  items: _categories.map((category) => DropdownMenuItem(
                    value: category, child: Text(_categoryDisplay(category)),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _source,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _tr('المصدر', 'Source'),
                    border: const OutlineInputBorder()),
                  items: {..._sources, _source}
                      .map((source) => DropdownMenuItem(
                            value: source,
                            child: Text(source.isEmpty
                                ? _tr('غير محدد', 'Unspecified')
                                : (widget.isEnglish && source == 'نقدي'
                                    ? 'Cash' : source)),
                          )).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _source = value);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('${_tr('التاريخ:', 'Date:')} ${formattedDate(_date)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLength: 250,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _tr('ملاحظات (اختياري)', 'Notes (optional)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('attach-receipt'),
                  onPressed: _chooseReceipt,
                  icon: const Icon(Icons.receipt_long),
                  label: Text(_receiptDataUrl.isEmpty
                      ? _tr('إضافة صورة إيصال أو فاتورة', 'Attach receipt image')
                      : _tr('تغيير صورة الإيصال', 'Change receipt image')),
                ),
                _receiptPreview(),
                if (_receiptDataUrl.isNotEmpty)
                  TextButton.icon(
                    key: const Key('remove-receipt'),
                    onPressed: () => setState(() => _receiptDataUrl = ''),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_tr('حذف صورة الإيصال', 'Remove receipt image')),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _excluded,
                  title: Text(_tr('استبعاد من إجمالي الشهر', 'Exclude from monthly totals')),
                  onChanged: (value) => setState(() => _excluded = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('save-transaction'),
                  onPressed: _save,
                  child: Text(_tr('حفظ المعاملة', 'Save transaction')),
                ),
                if (widget.original != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('delete-transaction'),
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(foregroundColor: current.error),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_tr('حذف المعاملة', 'Delete transaction')),
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
