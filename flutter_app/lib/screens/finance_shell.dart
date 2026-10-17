// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../finance/backup_codec.dart';
import '../finance/guest_migration.dart';
import '../finance/analytics_models.dart';
import 'premium_page.dart';
import '../finance/monthly_report.dart';
import '../finance/installment_calendar.dart';
import '../finance/due_notices.dart';
import '../finance/sms_import.dart';
import 'sms_import_review.dart';
import 'package:printing/printing.dart';
import '../finance/cloud_sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    this.guestStore,
    this.cloudEnabled = false,
    this.isDark = false,
    this.isEnglish = false,
    this.onToggleTheme,
    this.onToggleLanguage,
    this.onSignOut,
    this.onOpenAuth,
    this.accountEmail,
  });

  final List<FinanceEntry> entries;
  final TransactionStore? store;
  final TransactionStore? guestStore;
  final bool cloudEnabled;
  final bool isDark;
  final bool isEnglish;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onToggleLanguage;
  final VoidCallback? onSignOut;
  final VoidCallback? onOpenAuth;
  final String? accountEmail;

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
  int? _cloudRevision;
  String _autoSyncStatus = '';
  bool _cloudBusy = false;
  bool _loading = false;
  bool _saving = false;
  bool _reportBusy = false;
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

  String _lang(String arabic, String english) =>
      widget.isEnglish ? english : arabic;

  String _money(num value) => _formatter.format(value);
  String _currency(num value) => '${_money(value)} ج.م';

  FinanceSummary get _summary => FinanceSummary(_entries);

  InstallmentLedger get _currentLedger => InstallmentLedger(
    entries: _entries, installments: _plans,
    customCategories: _customCategories, prefs: _prefs,
    createdAt: _createdAt,
  );

  bool get _editable =>
      widget.store != null && !_loading && !_saving && !_cloudBusy &&
      _loadError == null;

  Future<void> _loadSavedTransactions() async {
    try {
      final store = widget.store!;
      final ledger = store is LedgerStore
          ? await store.loadLedger()
          : InstallmentLedger(entries: await store.load(), installments: const []);
      int? checkpoint;
      if (store is CloudRevisionStore) {
        try {
          checkpoint = await (store as CloudRevisionStore).readCloudRevision();
        } catch (_) {
          // A corrupt checkpoint blocks pushing previous changes, not
          // reading the financial ledger; never trust a bad revision.
          checkpoint = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _cloudRevision = checkpoint;
        _entries = ledger.entries;
        _plans = ledger.installments;
        _customCategories = ledger.customCategories;
        _prefs = ledger.prefs;
        _createdAt = ledger.createdAt;
        _loading = false;
      });
      if (widget.cloudEnabled) await _restoreCloudIfLocalEmpty();
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
      await _autoSyncAfterWrite();
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
      builder: (context) => TransactionEditor(
          original: original, customCategories: _customCategories),
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
        content: Text('تم حفظ التغيير على الجهاز.'),
      ));
      await _autoSyncAfterWrite();
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

  Future<void> _exportMonthlyReport() async {
    if (_reportBusy || _loading || _saving) return;
    setState(() => _reportBusy = true);
    try {
      final report = MonthlyReportData(month: _month, allEntries: _entries);
      final bytes = await MonthlyReportPdf.create(report);
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: report.filename);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر إنشاء تقرير PDF أو مشاركته على هذا الجهاز.'),
      ));
    } finally {
      if (mounted) setState(() => _reportBusy = false);
    }
  }

  Future<void> _importSmsFile() async {
    if (!_editable || widget.store is! LedgerStore) return;
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'رسائل SMS',
            extensions: ['txt', 'csv', 'json']),
      ]);
      if (file == null || !mounted || !_editable) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > SmsImportParser.maxBytes) {
        throw const FormatException('SMS file larger than 3 MB');
      }
      final records = SmsImportParser.read(utf8.decode(bytes), file.name);
      if (!mounted || !_editable) return;
      final imported = await Navigator.of(context).push<List<FinanceEntry>>(
        MaterialPageRoute(builder: (context) => SmsImportReview(
          records: records, existing: _entries,
        )),
      );
      if (imported == null || imported.isEmpty || !mounted || !_editable) return;
      final next = _currentLedger.withCollections(
        entries: [..._entries, ...imported],
        installments: _plans,
      );
      await _applyLedger(next, 'تم استيراد الرسائل المختارة على الجهاز فقط.');
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ملف الرسائل غير صالح أو كبير. اختار TXT أو CSV أو JSON، '
            'بحد أقصى 200 رسالة و3 ميجابايت.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر قراءة ملف SMS. مفيش بيانات اتغيرت.'),
      ));
    }
  }

  Future<void> _exportCalendar() async {
    if (_plans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أضف قسطًا واحدًا على الأقل لتصدير المواعيد.'),
      ));
      return;
    }
    try {
      final calendar = InstallmentCalendar.export(_plans, DateTime.now());
      const filename = 'hesabaty-installments.ics';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(
          Uint8List.fromList(utf8.encode(calendar)),
          mimeType: 'text/calendar', name: filename,
        )],
        fileNameOverrides: [filename],
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تجهيز مواعيد التقويم.'),
      ));
    }
  }

  Future<void> _addCustomCategory() async {
    if (!_editable || widget.store is! LedgerStore) return;
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تصنيف مخصص'),
        content: TextField(
          key: const Key('custom-category-input'),
          controller: input, maxLength: 40, autofocus: true,
          decoration: const InputDecoration(hintText: 'اسم التصنيف'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    input.dispose();
    if (name == null || !mounted || !_editable) return;
    if (name.isEmpty || name.length > 40 || _customCategories.contains(name) ||
        _customCategories.length >= 50) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الاسم مكرر أو غير صالح أو وصلت لـ50 تصنيف.'),
      ));
      return;
    }
    await _applyLedger(InstallmentLedger(
      entries: _entries, installments: _plans,
      customCategories: [..._customCategories, name],
      prefs: _prefs, createdAt: _createdAt,
    ), 'اتضاف التصنيف الجديد.');
  }

  Future<void> _removeCustomCategory(String value) async {
    if (!_editable || widget.store is! LedgerStore) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف التصنيف المخصص؟'),
        content: const Text('المعاملات القديمة هتحتفظ بتصنيفها، '
            'لكن مش هيظهر ضمن اختيارات المعاملات الجديدة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_editable) return;
    await _applyLedger(InstallmentLedger(
      entries: _entries, installments: _plans,
      customCategories: _customCategories.where((x) => x != value).toList(),
      prefs: _prefs, createdAt: _createdAt,
    ), 'التصنيف اتحذف من الاختيارات الجديدة.');
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
    // ListTiles and InkWells need their own Material ink surface above the
    // card background, otherwise taps can be invisible or trigger assertions.
    child: Material(type: MaterialType.transparency, child: child),
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

  Widget _dueNoticesPanel() {
    final notices = InstallmentDueNotices.upcoming(_plans, DateTime.now());
    if (notices.isEmpty) return const SizedBox.shrink();
    final overdue = notices.where((n) => n.daysLeft < 0).length;
    final today = notices.where((n) => n.daysLeft == 0).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _panel(child: Column(
        key: const Key('installment-due-alerts'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.notifications_active_outlined,
                color: overdue > 0 ? _red : _accent),
            const SizedBox(width: 8),
            Expanded(child: Text(
              overdue > 0 ? 'عندك ' + overdue.toString() + ' قسط متأخر'
                  : today > 0 ? 'عندك ' + today.toString() + ' قسط النهارده'
                  : 'أقساط مستحقة قريبًا',
              style: const TextStyle(fontWeight: FontWeight.w800),
            )),
            TextButton(
              onPressed: () => _goTo(2),
              child: const Text('عرض الأقساط')),
          ]),
          for (final n in notices.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(n.plan.name + ': ' + _currency(n.plan.amount) +
                  ' · ' + (n.daysLeft < 0 ? 'متأخر' :
                      n.daysLeft == 0 ? 'النهارده' :
                      'بعد ' + n.daysLeft.toString() + ' يوم'),
                style: TextStyle(color: _mutedText, fontSize: 12)),
            ),
          if (notices.length > 3)
            Text('وفيه ' + (notices.length - 3).toString() + ' قسط إضافي',
              style: TextStyle(color: _mutedText, fontSize: 12)),
        ],
      )),
    );
  }

  Widget _home() {
    final totals = _summary.totals(_month);
    final categories = _summary.categoryTotals(_month);
    final recent = _summary.recent(_month);
    return ListView(
      key: const Key('home-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        _hero(totals),
        _dueNoticesPanel(),
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
              () => _exportMonthlyReport())),
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
              () => _importSmsFile()),
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
        Text(_lang('المعاملات', 'Transactions'), style: const TextStyle(
            fontSize: 23, fontWeight: FontWeight.w800)),
        Text(_lang('تفاصيل كل سحب وإيداع، ومعاه إثبات العملية', 'All income and expense transactions'),
            style: TextStyle(fontSize: 12, color: _mutedText)),
        _monthPicker(),
        Wrap(spacing: 8, children: [
          _action('استيراد SMS', Icons.sms_outlined,
              () => _importSmsFile()),
          _action('تقرير PDF', Icons.download,
              () => _exportMonthlyReport()),
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
        Text(_lang('الأقساط', 'Installments'), style: const TextStyle(fontSize: 23,
            fontWeight: FontWeight.w800)),
        Text(_lang('مواعيد دفع الأقساط الشهرية، وتسجل السحب وقت الدفع فقط', 'Installment schedules and recorded payments'),
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
            '🔔 بنعرض الأقساط المستحقة عند فتح حساباتي. '
            'صدّر مواعيد الأقساط للتقويم وفعّل تنبيهاته '
            'علشان توصلك حتى لو حساباتي مقفول.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        const SizedBox(height: 13),
        Wrap(spacing: 9, children: [
          _action('＋ إضافة قسط', Icons.add, () => _editInstallment()),
          _action('تصدير للتقويم', Icons.calendar_month_outlined,
              () => _exportCalendar()),
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

  /// Mirrors the HTML v1.5 Analytics page, including its six-month chart,
  /// percentage-change edge cases, complete category list and key indicators.
  Widget _analytics() {
    final analysis = AnalyticsSummary(
      summary: _summary,
      selectedMonth: _month,
      today: DateTime.now(),
    );
    final comparison = analysis.comparison;
    final totals = analysis.current;
    final categories = analysis.categories;
    return ListView(
      key: const Key('analytics-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        const Text('التحليلات', style: TextStyle(
          fontSize: 23, fontWeight: FontWeight.w800,
        )),
        Text('اعرف فلوسك راحت فين وقارن بين الشهور',
            style: TextStyle(color: _mutedText, fontSize: 12)),
        _monthPicker(),
        _sectionTitle('حركة آخر 6 شهور'),
        _panel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sixMonthChart(analysis),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _analyticsLegend('الإيداع', _accent),
              const SizedBox(width: 20),
              _analyticsLegend('السحب', _red),
            ]),
          ],
        )),
        _sectionTitle('المقارنة الشهرية'),
        _panel(child: Column(
          children: [
            _analyticsRow('سحب الشهر الحالي',
                _currency(comparison.current.withdrawal),
                valueColor: _red),
            Divider(color: _line),
            _analyticsRow('سحب الشهر السابق',
                _currency(comparison.previous.withdrawal)),
            Divider(color: _line),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                comparison.describe(_money),
                key: const Key('expense-comparison'),
                style: TextStyle(
                  color: _mutedText, height: 1.8, fontSize: 12,
                ),
              ),
            ),
          ],
        )),
        _sectionTitle('توزيع المصروفات'),
        if (categories.isEmpty)
          _empty('مفيش مصروفات للتحليل في الشهر ده',
              Icons.trending_down_outlined)
        else
          _panel(child: Column(
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text(categories[i].key,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700))),
                      Text(_currency(categories[i].value),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      key: ValueKey('expense-category-${categories[i].key}'),
                      value: totals.withdrawal > 0
                          ? (categories[i].value / totals.withdrawal)
                              .clamp(0, 1)
                          : 0,
                      minHeight: 7,
                      backgroundColor: _alt,
                      color: _red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ]),
                ),
                if (i != categories.length - 1)
                  Divider(height: 1, color: _line),
              ],
            ],
          )),
        _sectionTitle('مؤشرات الشهر'),
        _panel(child: Column(children: [
          _analyticsRow(
            'نسبة المصروفات من الإيداعات',
            analysis.spendingShare == null
                ? '—'
                : '${_money(analysis.spendingShare!)}%',
            key: const Key('analytics-spending-share'),
          ),
          Divider(color: _line),
          _analyticsRow(
            'متبقي الشهر', _currency(totals.remaining),
            valueColor: totals.remaining < 0 ? _red : _green,
          ),
          Divider(color: _line),
          _analyticsRow(
            'عدد العمليات المسجلة', '${totals.transactionCount}',
            key: const Key('analytics-transaction-count'),
          ),
        ])),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _analyticsLegend(String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 11, height: 11,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: _mutedText)),
      ]);

  Widget _sixMonthChart(AnalyticsSummary analysis) {
    final maxValue = analysis.maxChartValue;
    final monthly = analysis.lastSixMonths;
    return SizedBox(
      key: const Key('six-month-chart'),
      height: 162,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < monthly.length; index++)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 132,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(child: _analyticsBar(
                          key: Key('month-$index-deposit'),
                          value: monthly[index].totals.deposit,
                          maxValue: maxValue,
                          color: _accent,
                          month: monthly[index].month,
                          title: 'الإيداع',
                        )),
                        const SizedBox(width: 3),
                        Flexible(child: _analyticsBar(
                          key: Key('month-$index-withdrawal'),
                          value: monthly[index].totals.withdrawal,
                          maxValue: maxValue,
                          color: _red,
                          month: monthly[index].month,
                          title: 'السحب',
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(arabicMonths[monthly[index].month.month - 1]
                          .substring(0, 3),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 10, color: _mutedText)),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _analyticsBar({
    required Key key,
    required double value,
    required double maxValue,
    required Color color,
    required DateTime month,
    required String title,
  }) {
    final scaled = value <= 0
        ? 2.0
        : (value / maxValue * 128).clamp(2.0, 128.0).toDouble();
    return Tooltip(
      message: '$title ${monthTitle(month)}: ${_currency(value)}',
      child: Container(
        key: key,
        width: 16,
        height: scaled,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6)),
        ),
      ),
    );
  }

  Widget _analyticsRow(String name, String value,
      {Color? valueColor, Key? key}) =>
      Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(name,
              style: TextStyle(color: _mutedText, fontSize: 12))),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(
              color: valueColor ?? _ink,
              fontWeight: FontWeight.w800, fontSize: 13)),
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

  Future<void> _rememberCloudRevision(int revision) async {
    final store = widget.store;
    if (store is CloudRevisionStore) {
      await (store as CloudRevisionStore).recordCloudRevision(revision);
    }
    if (!mounted) return;
    setState(() => _cloudRevision = revision);
  }

  Future<void> _restoreCloudIfLocalEmpty() async {
    if (!widget.cloudEnabled || _cloudBusy || !_editable ||
        _entries.isNotEmpty || _plans.isNotEmpty ||
        widget.store is! LedgerStore) {
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      final remote = await CloudFinanceSync(Supabase.instance.client).fetch();
      if (!mounted || remote == null || _entries.isNotEmpty ||
          _plans.isNotEmpty) {
        return;
      }
      await _replaceLedgerLocally(remote.ledger);
      if (!mounted) return;
      await _rememberCloudRevision(remote.revision);
      if (mounted) {
        setState(() =>
          _autoSyncStatus = 'تم استرجاع بيانات الحساب تلقائيًا.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _autoSyncStatus =
          'تعذر الاسترجاع التلقائي. بيانات الجهاز زي ما هي.');
      }
    } finally {
      if (mounted) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Future<void> _autoSyncAfterWrite() async {
    if (!widget.cloudEnabled || _cloudBusy || !mounted ||
        widget.store is! LedgerStore) {
      return;
    }
    final local = _currentLedger;
    final checkpoint = _cloudRevision;
    setState(() {
      _cloudBusy = true;
      _autoSyncStatus = 'جاري محاولة المزامنة...';
    });
    try {
      final client = Supabase.instance.client;
      final accountId = client.auth.currentUser?.id;
      if (accountId == null || client.auth.currentSession == null) return;
      final service = CloudFinanceSync(client);
      final remote = await service.fetch();
      if (!mounted || client.auth.currentUser?.id != accountId) return;
      if (remote != null &&
          (checkpoint == null || remote.revision != checkpoint)) {
        setState(() => _autoSyncStatus =
            'تعارض بين الأجهزة: التعديلات محفوظة محليًا. '
            'الرفع اتوقف علشان مانمسحش نسخة أحدث.');
        return;
      }
      if (remote == null && checkpoint != null) {
        setState(() => _autoSyncStatus =
            'السحابة اتغيرت. بياناتك محفوظة على الجهاز.');
        return;
      }
      final revision = await service.push(local, expectedRevision: checkpoint);
      if (!mounted || client.auth.currentUser?.id != accountId) return;
      await _rememberCloudRevision(revision);
      if (mounted) {
        setState(() =>
          _autoSyncStatus = 'تم حفظ آخر التعديلات سحابيًا.');
      }
    } on FormatException {
      if (mounted) {
        setState(() => _autoSyncStatus =
            'حجم بيانات الحساب أكبر من 8 ميجابايت؛ '
            'البيانات محفوظة على الموبايل لكن مش اترفعت للسحابة. '
            'صدّر نسخة احتياطية وصغّر صور الإيصالات.');
      }
    } on CloudConflict {
      if (mounted) {
        setState(() => _autoSyncStatus =
          'جهاز آخر سبقك بتعديلات. تم إيقاف الرفع دون فقد بيانات.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _autoSyncStatus =
          'الإنترنت أو السحابة غير متاحين. التعديل محفوظ محليًا.');
      }
    } finally {
      if (mounted) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Future<void> _syncCloudNow() async {
    if (!_editable || _cloudBusy || widget.store is! LedgerStore) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    setState(() => _cloudBusy = true);
    try {
      final sync = CloudFinanceSync(client);
      final remote = await sync.fetch();
      if (!mounted) return;
      final local = _currentLedger;
      final hasLocal = local.entries.isNotEmpty || local.installments.isNotEmpty;
      if (remote == null) {
        if (!hasLocal) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('مفيش معاملات محلية أو سحابية للمزامنة.'),
          ));
          return;
        }
        final confirm = await _confirmCloudAction(
          title: 'رفع أول نسخة للسحابة؟',
          description: 'ده أول حفظ سحابي للحساب. بيانات جهازك هتفضل '
              'محفوظة محليًا. مش هنرفع أي بيانات إلا بعد موافقتك.',
          approve: 'رفع البيانات',
        );
        if (confirm != true || !mounted) return;
        final revision = await sync.push(local, expectedRevision: null);
        if (!mounted) return;
        await _rememberCloudRevision(revision);
        if (!mounted) return;
        _showCloudMessage('اتحفظت نسخة على حسابك السحابي.');
        return;
      }
      // A remote snapshot is never overwritten based on stale local state.
      if (!hasLocal) {
        final confirm = await _confirmCloudAction(
          title: 'استرجاع بيانات الحساب؟',
          description: 'لقينا ${remote.ledger.entries.length} معاملة '
              'و${remote.ledger.installments.length} قسط على السحابة. '
              'جهازك الحالي فاضي. تحب تنزّلهم على الجهاز؟',
          approve: 'تنزيل النسخة',
        );
        if (confirm != true || !mounted) return;
        await _replaceLedgerLocally(remote.ledger);
        if (!mounted) return;
        await _rememberCloudRevision(remote.revision);
        if (!mounted) return;
        _showCloudMessage('تم تنزيل بيانات الحساب على الجهاز.');
        return;
      }
      // Compare stable data, not export timestamps added to backup envelopes.
      Map<String, dynamic> dataOf(InstallmentLedger ledger) => {
        'transactions': ledger.entries.map((e) => e.toJson()).toList(),
        'installments': ledger.installments.map((e) => e.toJson()).toList(),
        'customCategories': ledger.customCategories,
        'prefs': ledger.prefs,
        'createdAt': ledger.createdAt,
      };
      final localData = dataOf(local);
      final remoteData = dataOf(remote.ledger);
      if (jsonEncode(localData) == jsonEncode(remoteData)) {
        await _rememberCloudRevision(remote.revision);
        if (!mounted) return;
        _showCloudMessage('نسخة الجهاز والسحابة متطابقتين.');
        return;
      }
      if (_cloudRevision != null && _cloudRevision == remote.revision) {
        final confirm = await _confirmCloudAction(
          title: 'رفع تعديلات الجهاز؟',
          description: 'نسخة السيرفر بنفس الإصدار اللي اتراجع قبل كده. '
              'رفع تعديلات الجهاز هيستبدل النسخة السحابية الحالية، '
              'بس لو جهاز آخر حفظ نسخة أحدث هيترفض الرفع لحمايتك.',
          approve: 'رفع التعديلات',
        );
        if (confirm != true || !mounted) return;
        final revision = await sync.push(
          local, expectedRevision: remote.revision,
        );
        if (!mounted) return;
        await _rememberCloudRevision(revision);
        if (!mounted) return;
        _showCloudMessage('تم رفع التغييرات بأمان.');
      } else {
        _showCloudMessage('في بيانات مختلفة على الجهاز والسحابة. '
            'المزامنة اتوقفت بدون استبدال أي بيانات. '
            'احفظ نسخة احتياطية وراجع الاختلاف قبل الاختيار.');
      }
    } on CloudConflict {
      if (!mounted) return;
      setState(() => _cloudRevision = null);
      if (widget.store is CloudRevisionStore) {
        try {
          await (widget.store! as CloudRevisionStore).clearCloudRevision();
        } catch (_) {
          // The server still rejects stale updates even if clearing fails.
        }
      }
      if (!mounted) return;
      _showCloudMessage('اتحفظت نسخة أحدث من جهاز تاني. '
          'مش هنكتب فوقها. راجع الفرق الأول.');
    } catch (_) {
      if (!mounted) return;
      _showCloudMessage('تعذرت المزامنة. '
          'بيانات الجهاز اتسابت زي ما هي.');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<bool?> _confirmCloudAction({
    required String title,
    required String description,
    required String approve,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(approve)),
      ],
    ),
  );

  Future<void> _replaceLedgerLocally(InstallmentLedger ledger) async {
    final store = widget.store! as LedgerStore;
    if (store is BackupRestorableStore) {
      await (store as BackupRestorableStore).replaceFromBackup(ledger);
    } else {
      await store.saveLedger(ledger);
    }
    if (!mounted) return;
    setState(() {
      _entries = ledger.entries;
      _plans = ledger.installments;
      _customCategories = ledger.customCategories;
      _prefs = ledger.prefs;
      _createdAt = ledger.createdAt;
    });
  }

  void _showCloudMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _importGuestData() async {
    if (!_editable || widget.guestStore is! LedgerStore ||
        widget.store is! LedgerStore || !widget.cloudEnabled) {
      return;
    }
    try {
      final guest = await (widget.guestStore! as LedgerStore).loadLedger();
      if (!mounted || !_editable) return;
      final checked = GuestMigration.prepare(
        guest: guest, account: _currentLedger);
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('نقل بيانات الضيف لحسابك؟'),
          content: Text(
            'بيانات الضيف فيها ${checked.entries.length} معاملة، '
            'و${checked.installments.length} قسط، '
            'و${checked.customCategories.length} تصنيف مخصص.\n\n'
            'النقل هيحفظ نسخة في حسابك من غير ما يمسح بيانات الضيف. '
            'مش هنستبدل حساب فيه معاملات بالفعل، '
            'ولو في نسخة سحابية مختلفة الرفع هيقف.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
            FilledButton(
              key: const Key('confirm-guest-migration'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد النقل')),
          ],
        ),
      );
      if (approved != true || !mounted || !_editable) return;
      // Re-check the destination immediately before touching its storage.
      final current = await (widget.store! as LedgerStore).loadLedger();
      final next = GuestMigration.prepare(guest: guest, account: current);
      await _replaceLedgerLocally(next);
      if (!mounted) return;
      _showCloudMessage('اتنسخت البيانات للحساب على الجهاز، '
          'وبيانات الضيف الأصلية لسه موجودة.');
      await _autoSyncAfterWrite();
    } on StateError {
      if (!mounted) return;
      _showCloudMessage('النقل يحتاج حسابًا فارغًا وبيانات ضيف موجودة. '
          'للحساب غير الفارغ، صدّر نسخة احتياطية بدل الاستبدال.');
    } on FormatException {
      if (!mounted) return;
      _showCloudMessage('بيانات الضيف غير صالحة للنقل. مفيش بيانات اتغيرت.');
    } catch (_) {
      if (!mounted) return;
      _showCloudMessage('تعذر النقل. احتفظ بالبيانات على الجهازين.');
    }
  }

  String _cloudQuotaLabel() {
    try {
      final size = CloudSnapshotBudget.estimateBytes(_currentLedger);
      final used = (size / (1024 * 1024)).toStringAsFixed(2);
      return !CloudSnapshotBudget.fits(size)
          ? 'النسخة المحلية حوالي ' + used +
              ' MB؛ تعدّت الحد السحابي (8 MB). '
              'صدّر نسخة احتياطية وصغّر صور الإيصالات.'
          : CloudSnapshotBudget.nearLimit(size)
              ? 'تنبيه: مستخدم ' + used +
                  ' MB من 8 MB متاحة للمزامنة السحابية.'
              : 'حجم بيانات الحساب للسحابة: ' + used +
                  ' MB من 8 MB.';
    } catch (_) {
      return 'حجم البيانات كبير جدًا أو فيه خطأ يمنع تقدير مساحة السحابة.';
    }
  }

  Widget _settings() => ListView(
    key: const Key('settings-page'),
    padding: const EdgeInsets.all(18),
    children: [
      Text(_lang('الإعدادات', 'Settings'), style: const TextStyle(fontSize: 23,
          fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      _panel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.cloudEnabled) ...[
            ListTile(
              key: const Key('account-status'),
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('الحساب متصل'),
              subtitle: Text(widget.accountEmail ?? 'تم تسجيل الدخول'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('بيانات الحساب منفصلة عن معاملات الضيف المحفوظة '
                  'على نفس الموبايل. المزامنة اختيارية.',
                  style: TextStyle(fontSize: 12)),
            ),
          ] else ...[
            const ListTile(
              key: Key('guest-account-status'),
              leading: Icon(Icons.person_outline),
              title: Text('استخدام كضيف — بدون حساب'),
              subtitle: Text('حساباتي شغال عادي، ومش مطلوب تسجيل الدخول.'),
            ),
            if (widget.onOpenAuth != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('التسجيل اختياري للمزامنة. '
                    'معاملات الضيف بتفضل محفوظة على جهازك '
                    'ومش بتتنقل للحساب تلقائيًا.',
                    style: TextStyle(fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FilledButton.icon(
                  key: const Key('login-from-settings'),
                  onPressed: widget.onOpenAuth,
                  icon: const Icon(Icons.login),
                  label: const Text('تسجيل الدخول أو إنشاء حساب'),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('المزامنة غير مفعلة في نسخة الاختبار دي.',
                    style: TextStyle(fontSize: 12)),
              ),
          ],
          const Divider(),
          ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(_lang('الوضع الداكن', 'Dark mode')),
          trailing: Switch(
            value: widget.isDark,
            onChanged: (_) => widget.onToggleTheme?.call(),
          ),
          onTap: widget.onToggleTheme,
        ),
        Divider(color: _line),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(_lang('اللغة', 'Language')),
          subtitle: Text(widget.isEnglish ? 'English (preview)' : 'العربية'),
          onTap: widget.onToggleLanguage,
        ),
        if (widget.onSignOut != null) ...[
          Divider(color: _line),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(_lang('تسجيل الخروج', 'Sign out')),
            onTap: widget.onSignOut,
          ),
        ],
      ])),
      const SizedBox(height: 16),
      if (widget.cloudEnabled && widget.guestStore is LedgerStore) ...[
        _panel(child: ListTile(
          key: const Key('import-guest-data'),
          leading: const Icon(Icons.move_to_inbox_outlined),
          title: const Text('نقل بيانات الضيف لحسابي'),
          subtitle: const Text('بموافقتك، من غير مسح النسخة الأصلية'),
          trailing: const Icon(Icons.chevron_left),
          onTap: _editable ? _importGuestData : null,
        )),
        const SizedBox(height: 16),
      ],
      if (widget.cloudEnabled)
        _panel(child: ListTile(
          key: const Key('premium-settings'),
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('حساباتي Premium'),
          subtitle: const Text('الاشتراك عبر Google Play والتحقق من السيرفر'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const PremiumPage()),
          ),
        )),
      const SizedBox(height: 16),
      if (widget.cloudEnabled)
        _panel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('الحساب السحابي',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('مزامنة يدوية تجريبية. لن ندمج أو نستبدل '
                'بيانات جهازين مختلفين تلقائيًا.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('sync-cloud'),
              onPressed: _editable && !_cloudBusy ? _syncCloudNow : null,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('مراجعة ومزامنة حسابي الآن'),
            ),
            Text(_cloudQuotaLabel(),
                key: const Key('cloud-quota-label'),
                style: const TextStyle(fontSize: 12)),
            if (_autoSyncStatus.isNotEmpty)
              Text(_autoSyncStatus, key: const Key('cloud-sync-status'),
                style: const TextStyle(fontSize: 12)),
            if (_cloudBusy) const LinearProgressIndicator(),
          ],
        )),
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
      _panel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('التصنيفات المخصصة',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          for (final category in _customCategories)
            ListTile(
              title: Text(category),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'حذف التصنيف',
                onPressed: _editable
                    ? () => _removeCustomCategory(category) : null,
              ),
            ),
          OutlinedButton.icon(
            key: const Key('add-custom-category'),
            onPressed: _editable ? _addCustomCategory : null,
            icon: const Icon(Icons.add),
            label: const Text('إضافة تصنيف جديد'),
          ),
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
            Text(_lang('أهلًا بيك 👋', 'Welcome 👋'),
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            Text(_lang('فلوسك في مكان واحد', 'Your money in one place'),
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
            tooltip: _lang('تغيير المظهر', 'Toggle theme'),
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDark
                ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          IconButton(
            key: const Key('settings-action'),
            tooltip: _lang('الإعدادات', 'Settings'),
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
                _loadError ?? widget.cloudEnabled
                    ? _lang('نسخة اختبار: الحفظ المحلي والمزامنة السحابية قيد التحقق. احتفظ بنسخة احتياطية.', 'Preview: cloud sync is not fully verified; keep a backup.')
                    : _lang('نسخة تجريبية: معاملات الضيف محفوظة على هذا الجهاز فقط. احتفظ بنسخة احتياطية.', 'Preview: guest transactions are saved on this device only.'),
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
            _tab(_lang('الرئيسية', 'Home'), Icons.home_outlined, 0),
            _tab(_lang('المعاملات', 'Transactions'), Icons.receipt_long_outlined, 1),
            const SizedBox(width: 64),
            _tab(_lang('الأقساط', 'Installments'), Icons.calendar_month_outlined, 2),
            _tab(_lang('التحليلات', 'Analytics'), Icons.bar_chart_outlined, 3),
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
        tooltip: _lang('إضافة معاملة جديدة', 'Add transaction'),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}
