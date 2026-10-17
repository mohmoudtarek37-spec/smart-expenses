import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../finance/backup_codec.dart';
import '../finance/finance_models.dart';
import '../finance/installment_models.dart';
import '../finance/transaction_store.dart';
import 'transaction_editor.dart';
import 'installment_editor.dart';
import 'package:uuid/uuid.dart';

/// Flutter reimplementation of the HTML v1.5 home/navigation structure.
/// Supports an opt-in, account-isolated preview transaction store. No cloud sync yet.
class FinanceShell extends StatefulWidget {
  const FinanceShell({
    super.key,
    this.entries = const [],
    this.store,
    this.isDark = false,
    this.onToggleTheme,
    this.onSignOut,
  });

  final List<FinanceEntry> entries;
  final TransactionStore? store;
  final bool isDark;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onSignOut;

  @override
  State<FinanceShell> createState() => _FinanceShellState();
}

enum _Filter { all, deposit, withdrawal }

class _FinanceShellState extends State<FinanceShell> {
  static const _muted = Color(0xFF607285);
  static const _mutedDark = Color(0xFFABB3C5);
  static const _red = Color(0xFFC63E55);
  static const _green = Color(0xFF25846A);
  static const _blue = Color(0xFF1767B0);
  final _formatter = NumberFormat.decimalPattern('en');
  final _search = TextEditingController();
  late DateTime _month;
  late List<FinanceEntry> _entries;
  List<InstallmentPlan> _plans = [];
  List<String> _customCategories = [];
  Map<String, dynamic> _prefs = {};
  String _createdAt = '';
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  int _selected = 0;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _month = DateTime(today.year, today.month, 1);
    _formatter.maximumFractionDigits = 2;
    _entries = List.of(widget.entries);
    if (widget.store != null) {
      _loading = true;
      _loadSavedTransactions();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color get _accent => widget.isDark
      ? const Color(0xFFFFE55D)
      : const Color(0xFFD4A600);
  Color get _ink => widget.isDark
      ? const Color(0xFFF5F5F7)
      : const Color(0xFF172534);
  Color get _mutedText => widget.isDark ? _mutedDark : _muted;
  Color get _surface => widget.isDark
      ? const Color(0xFF1B1C26)
      : Colors.white;
  Color get _background => widget.isDark
      ? const Color(0xFF0D0E14)
      : Colors.white;
  Color get _line => widget.isDark
      ? const Color(0xFF303242)
      : const Color(0xFFE3E9EF);
  Color get _alt => widget.isDark
      ? const Color(0xFF262833)
      : const Color(0xFFF5F7FA);

  String _money(num value) => _formatter.format(value);
  String _currency(num value) => '${_money(value)} ج.م';

  FinanceSummary get _summary => FinanceSummary(_entries);

  InstallmentLedger get _currentLedger => InstallmentLedger(
    entries: _entries, installments: _plans,
    customCategories: _customCategories, prefs: _prefs,
    createdAt: _createdAt,
  );

  bool get _editable =>
      widget.store != null && !_loading && !_saving && _loadError == null;

  Future<void> _loadSavedTransactions() async {
    try {
      final store = widget.store!;
      final ledger = store is LedgerStore
          ? await store.loadLedger()
          : InstallmentLedger(entries: await store.load(), installments: const []);
      if (!mounted) return;
      setState(() {
        _entries = ledger.entries;
        _plans = ledger.installments;
        _customCategories = ledger.customCategories;
        _prefs = ledger.prefs;
        _createdAt = ledger.createdAt;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذر قراءة البيانات المحلية. لن نسمح بحفظ جديد قبل حل المشكلة.';
      });
    }
  }

  Future<void> _applyLedger(InstallmentLedger next, String successMessage) async {
    if (!_editable || widget.store is! LedgerStore) return;
    setState(() => _saving = true);
    try {
      await (widget.store! as LedgerStore).saveLedger(next);
      if (!mounted) return;
      setState(() {
        _entries = next.entries;
        _plans = next.installments;
        _customCategories = next.customCategories;
        _prefs = next.prefs;
        _createdAt = next.createdAt;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(successMessage),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فشل حفظ التغيير. البيانات القديمة لم تتغير.'),
      ));
    }
  }

  Future<void> _editInstallment([InstallmentPlan? original]) async {
    if (!_editable || widget.store is! LedgerStore) {
      _comingSoon('إدارة الأقساط');
      return;
    }
    final result = await showModalBottomSheet<InstallmentEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => InstallmentEditor(original: original, month: _month),
    );
    if (result == null || !mounted || !_editable) return;
    var ledger = _currentLedger;
    if (result.action == InstallmentEditAction.delete) {
      if (original == null) return;
      ledger = ledger.withoutPlan(original.id);
    } else {
      try {
        ledger = ledger.withPlan(result.plan!);
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذر تعديل القسط بسبب وجود دفعات خارج مدة القسط.'),
        ));
        return;
      }
    }
    await _applyLedger(ledger, 'تم حفظ الأقساط على الجهاز فقط.');
  }

  Future<void> _payInstallment(InstallmentPlan plan) async {
    if (!_editable || widget.store is! LedgerStore ||
        plan.paymentFor(_month) != null) {
      return;
    }
    final eligible = _entries.where((entry) =>
        entry.type == EntryType.withdrawal && !entry.excluded &&
        FinanceSummary.sameMonth(entry.date, _month) &&
        (entry.amount - plan.amount).abs() <= 0.011 &&
        entry.linkedInstallment.isEmpty).toList();
    final option = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('تسجيل دفع القسط'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: Text('${plan.name} — ${_currency(plan.amount)}'),
          ),
          SimpleDialogOption(
            key: const Key('pay-new-withdrawal'),
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('إنشاء عملية سحب جديدة'),
          ),
          for (final entry in eligible)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.id),
              child: Text('ربط بسحب موجود: ${entry.title} — '
                  '${formattedDate(entry.date)}'),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Text('اختار السحب الموجود لو مبلغ البنك مسجل بالفعل '
                'عشان مايتحسبش مرتين.', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    if (option == null || !mounted || !_editable) return;
    final payDate = FinanceSummary.sameMonth(DateTime.now(), _month)
        ? DateTime.now() : plan.dueDate(_month);
    try {
      final ledger = _currentLedger.recordPayment(
        installmentId: plan.id, month: _month, paidOn: payDate,
        newTransactionId: const Uuid().v4(),
        existingTransactionId: option == 'new' ? null : option,
      );
      await _applyLedger(ledger, 'تم تسجيل دفع القسط بدون تكرار السحب.');
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تسجيل القسط. راجع المعاملات وحالة الدفع.'),
      ));
    }
  }

  Future<void> _undoInstallmentPayment(InstallmentPlan plan) async {
    if (!_editable || widget.store is! LedgerStore) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء تسجيل الدفع؟'),
        content: const Text('السحب اللي أنشأه التطبيق لهذا القسط هيتحذف. '
            'أما السحب الموجود اللي ربطته بالقسط هيفضل محفوظ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد إلغاء الدفع')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_editable) return;
    try {
      final ledger = _currentLedger.undoPayment(installmentId: plan.id, month: _month);
      await _applyLedger(ledger, 'تم إلغاء تسجيل الدفع.');
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر إلغاء دفع هذا القسط.'),
      ));
    }
  }

  Future<void> _editTransaction({FinanceEntry? original}) async {
    if (!_editable || original?.linkedInstallment.isNotEmpty == true) {
      _comingSoon('فك ارتباط دفعة القسط أولًا قبل تعديلها');
      return;
    }
    final result = await showModalBottomSheet<TransactionEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => TransactionEditor(original: original),
    );
    if (result == null || !mounted || !_editable) return;
    final next = List<FinanceEntry>.from(_entries);
    if (result.action == TransactionEditAction.delete) {
      if (original == null) return;
      next.removeWhere((entry) => entry.id == original.id);
    } else {
      final entry = result.entry!;
      if (original == null) {
        next.add(entry);
      } else {
        final index = next.indexWhere((item) => item.id == original.id);
        if (index < 0) return;
        next[index] = entry;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.store!.save(next);
      if (!mounted) return;
      setState(() {
        _entries = next;
        _saving = false;
        if (result.entry != null) {
          _month = DateTime(result.entry!.date.year, result.entry!.date.month);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حفظ التغيير على الجهاز فقط، بدون مزامنة سحابية.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فشل حفظ التغيير. البيانات المعروضة لم تتغير.'),
      ));
    }
  }

  void _goTo(int page, {_Filter filter = _Filter.all}) {
    setState(() {
      _selected = page;
      _filter = filter;
      _search.clear();
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature — قيد النقل من نسخة HTML. المعاينة لا تحفظ بيانات.'),
    ));
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding,
      Color? background, Border? border}) => Container(
    decoration: BoxDecoration(
      color: background ?? _surface,
      borderRadius: BorderRadius.circular(19),
      border: border ?? Border.all(color: _line),
    ),
    padding: padding ?? const EdgeInsets.all(16),
    child: child,
  );

  Widget _sectionTitle(String title, {String? action, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(top: 23, bottom: 12),
        child: Row(
          children: [
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 17,
                    fontWeight: FontWeight.w800))),
            if (action != null)
              TextButton(onPressed: onTap,
                  child: Text(action, style: TextStyle(color: _accent,
                      fontWeight: FontWeight.w700))),
          ],
        ),
      );

  Widget _monthPicker() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: _panel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          IconButton(
            key: const Key('previous-month'),
            tooltip: 'الشهر السابق',
            onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(child: Text('🗓  ${monthTitle(_month)}',
              key: const Key('current-month'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700))),
          IconButton(
            key: const Key('next-month'),
            tooltip: 'الشهر التالي',
            onPressed: () => setState(() => _month = shiftMonth(_month, 1)),
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    ),
  );

  Widget _hero(MonthTotals totals) => InkWell(
    key: const Key('total-card'),
    onTap: () => _goTo(1, filter: _Filter.deposit),
    borderRadius: BorderRadius.circular(19),
    child: _panel(
      background: widget.isDark
          ? const Color(0xFF29281B)
          : const Color(0xFFFFF9DB),
      border: Border.all(color: widget.isDark
          ? const Color(0xFF5A5125)
          : const Color(0xFFF2E6AD)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_balance_wallet_outlined, color: _accent,
                size: 20),
            const SizedBox(width: 8),
            const Text('الإجمالي', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Text(_money(totals.deposit), key: const Key('total-deposit'),
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                  color: _ink)),
          Text('جنيه • إجمالي إيداعات الشهر',
              style: TextStyle(fontSize: 11, color: _mutedText)),
          const SizedBox(height: 20),
          Center(child: Column(children: [
            Text('نسبة المصروفات', style: TextStyle(
                fontSize: 12, color: _mutedText)),
            const SizedBox(height: 9),
            SizedBox(height: 112, width: 112,
              child: Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(
                  value: totals.ringPercentage / 100,
                  strokeWidth: 10,
                  backgroundColor: _alt,
                  color: _accent,
                  strokeCap: StrokeCap.round,
                ),
                Center(child: Text(
                  '${_money(totals.spendingPercentage)}%',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: _ink, fontSize: 18,
                      fontWeight: FontWeight.w800),
                )),
              ]),
            ),
            const SizedBox(height: 9),
            Text(totals.deposit <= 0
                ? 'أضف إيداعًا لعرض النسبة'
                : totals.remaining < 0
                    ? 'مصروفاتك تجاوزت الإيداعات'
                    : 'من إجمالي الإيداعات',
                style: TextStyle(color: _mutedText, fontSize: 11)),
          ])),
        ],
      ),
    ),
  );

  Widget _smallMetric({required String title, required String value,
      required IconData icon, required Color color, required VoidCallback onTap,
      Key? key}) => Expanded(child: InkWell(
    key: key,
    borderRadius: BorderRadius.circular(17),
    onTap: onTap,
    child: _panel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Expanded(child: Text(title, style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12,
            ))),
          ]),
          const SizedBox(height: 11),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, textDirection: TextDirection.ltr,
                style: TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 19, color: color)),
          ),
          const SizedBox(height: 4),
          Text('جنيه', style: TextStyle(fontSize: 10, color: _mutedText)),
        ],
      ),
    ),
  ));

  Widget _empty(String message, IconData icon) =>
      _panel(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Column(children: [
          Icon(icon, size: 36, color: _mutedText),
          const SizedBox(height: 9),
          Text(message, textAlign: TextAlign.center,
              style: TextStyle(color: _mutedText, fontSize: 13)),
        ])),
      ));

  Widget _categoryList(List<MapEntry<String, double>> categories,
      MonthTotals totals) {
    if (categories.isEmpty) {
      return _empty('لحد دلوقتي مفيش مصروفات في الشهر ده',
          Icons.bar_chart_outlined);
    }
    return _panel(child: Column(
      children: categories.take(6).map((category) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text(category.key,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700))),
              Text(_currency(category.value), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: totals.withdrawal <= 0 ? 0 :
                  (category.value / totals.withdrawal).clamp(0, 1),
              minHeight: 6,
              backgroundColor: _alt,
              color: _accent,
              borderRadius: BorderRadius.circular(20),
            ),
          ]),
        ),
      ).toList(),
    ));
  }

  Widget _entryRow(FinanceEntry entry) {
    final deposit = entry.type == EntryType.deposit;
    final icon = deposit ? Icons.south_west : Icons.north_east;
    final color = deposit ? _green : _red;
    return InkWell(
      onTap: () => _editTransaction(original: entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Container(height: 44, width: 44,
              decoration: BoxDecoration(color: _alt,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color)),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text('${formattedDate(entry.date)} · '
                  '${entry.source.isEmpty ? 'يدوي' : entry.source}'
                  '${entry.excluded ? ' · مستبعدة' : ''}',
                  style: TextStyle(color: _mutedText, fontSize: 11)),
            ],
          )),
          const SizedBox(width: 9),
          Text('${deposit ? '+' : '−'}${_money(entry.amount)}',
              textDirection: TextDirection.ltr,
              style: TextStyle(color: color, fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _entryList(List<FinanceEntry> entries, {String? emptyMessage}) {
    if (entries.isEmpty) {
      return _empty(emptyMessage ?? 'لا توجد معاملات مطابقة في هذا الشهر',
          Icons.receipt_long_outlined);
    }
    return _panel(child: Column(children: [
      for (var i = 0; i < entries.length; i++) ...[
        if (i != 0) Divider(height: 1, color: _line),
        _entryRow(entries[i]),
      ],
    ]));
  }

  Widget _action(String label, IconData icon, VoidCallback tap) =>
      OutlinedButton.icon(
        onPressed: tap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: BorderSide(color: _line),
          backgroundColor: _alt,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _home() {
    final totals = _summary.totals(_month);
    final categories = _summary.categoryTotals(_month);
    final recent = _summary.recent(_month);
    return ListView(
      key: const Key('home-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        _hero(totals),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _smallMetric(key: const Key('withdrawal-card'), title: 'السحب',
            value: _money(totals.withdrawal), icon: Icons.north_east,
            color: _red, onTap: () => _goTo(1,
                filter: _Filter.withdrawal)),
          const SizedBox(width: 8),
          _smallMetric(title: 'الإيداع', value: _money(totals.deposit),
            icon: Icons.south_west, color: _blue,
            onTap: () => _goTo(1, filter: _Filter.deposit)),
          const SizedBox(width: 8),
          _smallMetric(title: 'المتبقي', value: _money(totals.remaining),
            icon: Icons.radio_button_checked,
            color: totals.remaining < 0 ? _red : _green,
            onTap: () => _goTo(1)),
        ]),
        _monthPicker(),
        Align(alignment: Alignment.centerRight,
          child: _action('تحميل تقرير PDF للشهر', Icons.download_outlined,
              () => _comingSoon('تقارير PDF'))),
        _sectionTitle('المصروفات حسب التصنيف',
            action: 'التفاصيل ←', onTap: () => _goTo(3)),
        _categoryList(categories, totals),
        _sectionTitle('آخر المعاملات',
            action: 'عرض الكل ←', onTap: () => _goTo(1)),
        _entryList(recent,
            emptyMessage: 'أضف أول معاملة أو استورد رسالة SMS'),
        const SizedBox(height: 13),
        Wrap(spacing: 8, children: [
          _action('استيراد رسائل SMS', Icons.sms_outlined,
              () => _comingSoon('استيراد SMS')),
          _action('الأقساط', Icons.calendar_month_outlined,
              () => _goTo(2)),
        ]),
      ],
    );
  }

  Widget _transactions() {
    var entries = _summary.monthEntries(_month);
    if (_filter != _Filter.all) {
      final type = _filter == _Filter.deposit
          ? EntryType.deposit : EntryType.withdrawal;
      entries = entries.where((entry) => entry.type == type).toList();
    }
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      entries = entries.where((entry) =>
          [entry.title, entry.category, entry.source, entry.note]
          .any((value) => value.toLowerCase().contains(query))).toList();
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    return ListView(
      key: const Key('transactions-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        const Text('المعاملات', style: TextStyle(
            fontSize: 23, fontWeight: FontWeight.w800)),
        Text('تفاصيل كل سحب وإيداع، ومعاه إثبات العملية',
            style: TextStyle(fontSize: 12, color: _mutedText)),
        _monthPicker(),
        Wrap(spacing: 8, children: [
          _action('استيراد SMS', Icons.sms_outlined,
              () => _comingSoon('استيراد SMS')),
          _action('تقرير PDF', Icons.download,
              () => _comingSoon('تقرير PDF')),
          _action('معاملة يدوية', Icons.add,
              () => _editTransaction()),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 7, children: [
          _chip('الكل', _Filter.all),
          _chip('↗ السحب', _Filter.withdrawal),
          _chip('↙ الإيداع', _Filter.deposit),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'بحث بالاسم أو المصدر أو النص...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _entryList(entries),
      ],
    );
  }

  Widget _chip(String label, _Filter filter) => ChoiceChip(
    label: Text(label),
    selected: _filter == filter,
    selectedColor: widget.isDark
        ? const Color(0xFF514820)
        : const Color(0xFFFFF5C7),
    onSelected: (_) => setState(() => _filter = filter),
    shape: StadiumBorder(side: BorderSide(color: _line)),
  );

  Widget _installments() {
    final summary = InstallmentMonthSummary(_plans, _month);
    final today = DateTime.now();
    return ListView(
      key: const Key('installments-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        const Text('الأقساط', style: TextStyle(fontSize: 23,
            fontWeight: FontWeight.w800)),
        Text('مواعيد دفع الأقساط الشهرية، وتسجل السحب وقت الدفع فقط',
            style: TextStyle(fontSize: 12, color: _mutedText)),
        _monthPicker(),
        Row(children: [
          _smallMetric(title: 'أقساط الشهر',
              value: _money(summary.total), icon: Icons.calendar_month,
              color: _blue, onTap: () {}),
          const SizedBox(width: 9),
          _smallMetric(title: 'المتبقي دفعه',
              value: _money(summary.remaining),
              icon: Icons.schedule_outlined,
              color: summary.remaining > 0 ? _red : _green,
              onTap: () {}),
        ]),
        const SizedBox(height: 16),
        _panel(
          background: _alt,
          child: const Text(
            '🔔 الاستحقاقات بتظهر عند فتح التطبيق. التنبيهات وقت إغلاقه '
            'وتصدير المواعيد للتقويم لسه قيد التطوير.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        const SizedBox(height: 13),
        Wrap(spacing: 9, children: [
          _action('＋ إضافة قسط', Icons.add, () => _editInstallment()),
          _action('تصدير للتقويم', Icons.calendar_month_outlined,
              () => _comingSoon('تصدير المواعيد للتقويم')),
        ]),
        _sectionTitle('الأقساط المسجلة'),
        if (summary.plans.isEmpty)
          _empty('مفيش أقساط مسجلة للشهر ده، ابدأ بإضافة أول قسط',
              Icons.calendar_month_outlined),
        for (final plan in summary.plans) ...[
          _installmentCard(plan, statusFor(plan, _month, today)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _installmentCard(InstallmentPlan plan, DueStatus dueStatus) {
    final paid = plan.paymentFor(_month) != null;
    final label = switch (dueStatus) {
      DueStatus.paid => 'مدفوع',
      DueStatus.overdue => 'متأخر',
      DueStatus.today => 'مستحق اليوم',
      DueStatus.upcoming => 'منتظر الدفع',
    };
    return _panel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.name, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15)),
              Text('يوم ${plan.dueDay} من كل شهر · '
                  '${plan.count == 0 ? 'مستمر' : '${plan.payments.length} من ${plan.count}'}',
                  style: TextStyle(fontSize: 11, color: _mutedText)),
            ],
          )),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700,
              color: paid ? _green : dueStatus == DueStatus.overdue
                  ? _red : _accent)),
        ]),
        const SizedBox(height: 14),
        Text(_currency(plan.amount), style: const TextStyle(
            fontSize: 23, fontWeight: FontWeight.w800),
            textDirection: TextDirection.ltr),
        if (plan.count > 0) ...[
          const SizedBox(height: 9),
          LinearProgressIndicator(
            value: (plan.payments.length / plan.count).clamp(0, 1),
            color: _accent, backgroundColor: _alt,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
        const SizedBox(height: 11),
        Text('الاستحقاق: ${formattedDate(plan.dueDate(_month))}',
            style: TextStyle(color: _mutedText, fontSize: 12)),
        const SizedBox(height: 9),
        Wrap(spacing: 8, runSpacing: 7, children: [
          if (!paid)
            _action('✓ تسجيل الدفع', Icons.check,
                () => _payInstallment(plan))
          else
            _action('إلغاء تسجيل الدفع', Icons.undo,
                () => _undoInstallmentPayment(plan)),
          _action('تعديل', Icons.edit_outlined,
              () => _editInstallment(plan)),
        ]),
      ],
    ));
  }

  Widget _analytics() {
    final totals = _summary.totals(_month);
    return ListView(
      key: const Key('analytics-page'),
      padding: const EdgeInsets.all(18),
      children: [
        const Text('التحليلات', style: TextStyle(fontSize: 23,
            fontWeight: FontWeight.w800)),
        _monthPicker(),
        _panel(child: Column(children: [
          _analyticsRow('الإيداعات', _currency(totals.deposit)),
          Divider(color: _line),
          _analyticsRow('المصروفات', _currency(totals.withdrawal)),
          Divider(color: _line),
          _analyticsRow('المتبقي', _currency(totals.remaining)),
        ])),
        _sectionTitle('المصروفات حسب التصنيف'),
        _categoryList(_summary.categoryTotals(_month), totals),
      ],
    );
  }

  Widget _analyticsRow(String name, String value) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(name)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  Future<void> _exportBackup() async {
    if (!_editable || widget.store is! LedgerStore) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصدير نسخة احتياطية'),
        content: const Text(
          'ملف JSON غير مشفّر، وهيحتوي على أرقامك ورسائل البنك '
          'وصور الإيصالات لو موجودة. احفظه في مكان خاص وآمن '
          'وما تشاركوش مع أي حد.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('اختيار مكان الحفظ')),
        ],
      ),
    );
    if (approved != true || !mounted || !_editable) return;
    try {
      final data = BackupCodec.encode(_currentLedger);
      final date = DateTime.now();
      final filename = 'hesabaty-backup-'
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}.json';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(
          Uint8List.fromList(utf8.encode(data)),
          mimeType: 'application/json',
          name: filename,
        )],
        fileNameOverrides: [filename],
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اختار من قائمة المشاركة مكان حفظ ملف JSON. '
            'احتفظ بالملف في مكان آمن.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تصدير النسخة الاحتياطية. راجع مساحة التخزين.'),
      ));
    }
  }

  Future<void> _importBackup() async {
    if (!_editable || widget.store is! LedgerStore) return;
    try {
      const jsonType = XTypeGroup(
        label: 'Hesabaty JSON',
        extensions: ['json'],
        mimeTypes: ['application/json'],
      );
      final file = await openFile(acceptedTypeGroups: [jsonType]);
      if (file == null || !mounted || !_editable) return;
      final content = await file.readAsBytes();
      if (content.length > BackupCodec.maxBackupBytes) {
        throw const FormatException('Backup file larger than 35 MB');
      }
      final preview = BackupCodec.decode(utf8.decode(content));
      if (!mounted || !_editable) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('مراجعة النسخة المستوردة'),
          content: SingleChildScrollView(
            child: Text(
              'إصدار الملف: ${preview.sourceVersion}\n'
              'معاملات الملف: ${preview.transactionCount}\n'
              'أقساط الملف: ${preview.installmentCount}\n'
              'رسائل البنك: ${preview.smsCount}\n'
              'الإيصالات: ${preview.receiptCount}\n\n'
              'الموجود عندك حاليًا: ${_entries.length} معاملة '
              'و${_plans.length} قسط.\n\n'
              'الاستيراد هيستبدل بيانات النسخة الحالية بالكامل. '
              'لو البيانات القديمة موجودة على جهاز تاني أو نسخة HTML '
              'مش هنلمسها. من الأفضل تصدير نسخة من البيانات الحالية الأول.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('confirm-backup-import'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('أؤكد الاستبدال'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_editable) return;
      setState(() => _saving = true);
      try {
        final store = widget.store! as LedgerStore;
        if (store is BackupRestorableStore) {
          await (store as BackupRestorableStore).replaceFromBackup(preview.ledger);
        } else {
          await store.saveLedger(preview.ledger);
        }
        if (!mounted) return;
        setState(() {
          _entries = preview.ledger.entries;
          _plans = preview.ledger.installments;
          _customCategories = preview.ledger.customCategories;
          _prefs = preview.ledger.prefs;
          _createdAt = preview.ledger.createdAt;
          _month = DateTime(DateTime.now().year, DateTime.now().month);
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم استيراد البيانات على هذا الجهاز فقط. '
              'المزامنة السحابية لسه قيد التطوير.'),
        ));
      } catch (_) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('فشل الاستيراد. البيانات المحلية القديمة لم تتغير.'),
        ));
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('الملف غير صالح أو فيه بيانات غير مدعومة: '
            '${error.message}'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر فتح الملف أو استيراده. بياناتك لم تتغير.'),
      ));
    }
  }

  Future<void> _restoreBeforeLastImport() async {
    if (!_editable || widget.store is! BackupRestorableStore) return;
    try {
      final before = await (widget.store! as BackupRestorableStore)
          .lastImportRestorePoint();
      if (!mounted) return;
      if (before == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('مفيش نسخة سابقة محفوظة قبل الاستيراد.'),
        ));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استعادة ما قبل آخر استيراد'),
          content: Text('هيتم استبدال البيانات الحالية '
              'ب${before.entries.length} معاملة '
              'و${before.installments.length} قسط '
              'كانوا موجودين قبل آخر استيراد. هل تؤكد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('استعادة')),
          ],
        ),
      );
      if (confirmed == true && mounted && _editable) {
        await _applyLedger(before, 'تمت استعادة بيانات ما قبل آخر استيراد.');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر فتح النسخة السابقة. البيانات الحالية لم تتغير.'),
      ));
    }
  }

  Widget _settings() => ListView(
    key: const Key('settings-page'),
    padding: const EdgeInsets.all(18),
    children: [
      const Text('الإعدادات', style: TextStyle(fontSize: 23,
          fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      _panel(child: Column(children: [
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('الوضع الداكن'),
          trailing: Switch(
            value: widget.isDark,
            onChanged: (_) => widget.onToggleTheme?.call(),
          ),
          onTap: widget.onToggleTheme,
        ),
        Divider(color: _line),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: const Text('اللغة'),
          subtitle: const Text('العربية — بننقل التبديل للإنجليزية'),
          onTap: () => _comingSoon('اللغة الإنجليزية'),
        ),
        if (widget.onSignOut != null) ...[
          Divider(color: _line),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('تسجيل الخروج'),
            onTap: widget.onSignOut,
          ),
        ],
      ])),
      const SizedBox(height: 16),
      _panel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('النسخ الاحتياطية',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          Text('تصدير أو استيراد ملف JSON. الاستيراد بيستبدل بيانات '
              'النسخة التجريبية بعد ما تراجع عدد المعاملات والأقساط.',
              style: TextStyle(color: _mutedText, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('export-backup'),
            onPressed: _editable && widget.store is LedgerStore
                ? _exportBackup : null,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('تصدير نسخة احتياطية'),
          ),
          OutlinedButton.icon(
            key: const Key('import-backup'),
            onPressed: _editable && widget.store is LedgerStore
                ? _importBackup : null,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('استيراد نسخة من HTML أو Flutter'),
          ),
          if (widget.store is BackupRestorableStore)
            TextButton.icon(
              key: const Key('undo-backup-import'),
              onPressed: _editable ? _restoreBeforeLastImport : null,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('استعادة البيانات قبل آخر استيراد'),
            ),
          const SizedBox(height: 8),
          const Text('تنبيه: ملف JSON غير مشفر. '
              'احفظه بعيدًا عن الآخرين، وما تعتمدش على النسخة الحالية '
              'كبديل لتطبيق حساباتي القديم.',
              style: TextStyle(fontSize: 11)),
        ],
      )),
      const SizedBox(height: 16),
      Text('حساباتي 2.0 — معاينة تطوير، مش بديل للنسخة الحالية.',
          style: TextStyle(color: _mutedText, fontSize: 12)),
    ],
  );

  Widget _tab(String label, IconData icon, int index) => Expanded(
    child: InkWell(
      onTap: () => _goTo(index),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 23, color: _selected == index ? _accent : _mutedText),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10,
              color: _selected == index ? _accent : _mutedText,
              fontWeight: _selected == index
                  ? FontWeight.w800 : FontWeight.w400)),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        toolbarHeight: 75,
        titleSpacing: 18,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أهلًا بيك 👋',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            Text('فلوسك في مكان واحد',
                style: TextStyle(fontSize: 11, color: _mutedText)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Language',
            onPressed: () => _comingSoon('اللغة الإنجليزية'),
            icon: const Text('EN', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'تغيير المظهر',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDark
                ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          IconButton(
            key: const Key('settings-action'),
            tooltip: 'الإعدادات',
            onPressed: () => _goTo(4),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (widget.store != null)
            Container(
              width: double.infinity,
              color: widget.isDark
                  ? const Color(0xFF3C331F)
                  : const Color(0xFFFFF4D7),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Text(
                _loadError ?? 'نسخة تجريبية: المعاملات محفوظة على الجهاز فقط، '
                    'بدون نسخ احتياطي أو مزامنة. لا تنقل إليها بياناتك المهمة بعد.',
                style: TextStyle(fontSize: 11,
                    color: widget.isDark ? Colors.white : Colors.black87),
              ),
            ),
          if (_loading || _saving) const LinearProgressIndicator(),
          Expanded(child: switch (_selected) {
            0 => _home(),
            1 => _transactions(),
            2 => _installments(),
            3 => _analytics(),
            _ => _settings(),
          }),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF15161D) : _surface,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Row(children: [
            _tab('الرئيسية', Icons.home_outlined, 0),
            _tab('المعاملات', Icons.receipt_long_outlined, 1),
            const SizedBox(width: 64),
            _tab('الأقساط', Icons.calendar_month_outlined, 2),
            _tab('التحليلات', Icons.bar_chart_outlined, 3),
          ]),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        key: const Key('add-transaction'),
        onPressed: () => _editTransaction(),
        backgroundColor: _accent,
        foregroundColor: const Color(0xFF222012),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        tooltip: 'إضافة معاملة جديدة',
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}
