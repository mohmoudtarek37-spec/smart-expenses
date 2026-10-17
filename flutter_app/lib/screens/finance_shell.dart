// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;

import '../finance/backup_codec.dart';
import '../finance/guest_migration.dart';
import '../finance/analytics_models.dart';
import 'premium_page.dart';
import 'account_profile_page.dart';
import '../finance/monthly_report.dart';
import '../finance/installment_calendar.dart';
import '../finance/due_notices.dart';
import '../finance/sms_import.dart';
import 'sms_import_review.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _FinanceShellState extends State<FinanceShell> with WidgetsBindingObserver {
  static const _muted = Color(0xFF4D6E87);
  static const _mutedDark = Color(0xFFC1D5E6);
  Color get _red => widget.isDark
      ? const Color(0xFFFF7893) : const Color(0xFFBF3752);
  Color get _green => widget.isDark
      ? const Color(0xFF48DDB2) : const Color(0xFF087F5B);
  Color get _blue => widget.isDark
      ? const Color(0xFF91D7FF) : const Color(0xFF176A9F);
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
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.cloudEnabled && _editable) {
      // Retry a locally preserved change after connectivity returns. A fetch
      // and revision check run first; never overwrite an unseen cloud edit.
      unawaited(_autoSyncAfterWrite());
    }
  }

  Color get _accent => widget.isDark
      ? const Color(0xFF99DAFF) : const Color(0xFF176496);
  Color get _ink => widget.isDark
      ? const Color(0xFFF1F8FF) : const Color(0xFF143652);
  Color get _mutedText => widget.isDark ? _mutedDark : _muted;
  Color get _surface => widget.isDark
      ? const Color(0xFF143A60) : const Color(0xFFEAF5FF);
  Color get _background => widget.isDark
      ? const Color(0xFF071C35) : const Color(0xFFD8EAF8);
  Color get _line => widget.isDark
      ? const Color(0x6686B7DF) : const Color(0xFFB5D4EC);
  Color get _alt => widget.isDark
      ? const Color(0xFF24517A) : const Color(0xFFD9EDFC);

  LinearGradient get _pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: widget.isDark
        ? [_background, const Color(0xFF153F68),
           const Color(0xFF0A2748), const Color(0xFF06192F)]
        : [const Color(0xFFBCD9EF), _background,
           const Color(0xFFEBF5FE), const Color(0xFFBCD9EF)],
    stops: const [0, 0.36, 0.7, 1],
  );

  String _lang(String arabic, String english) =>
      widget.isEnglish ? english : arabic;

  String _money(num value) => _formatter.format(value);
  static const currencyCodes = ['EGP','USD','EUR','AED','SAR','CAD','KWD','SEK','UAH','RUB'];
  String get _currencyCode => currencyCodes.contains(_prefs['currency'])
      ? _prefs['currency'] as String : 'EGP';
  String _currency(num value) => '${_money(value)} $_currencyCode';

  String get _displayName {
    final profile = _prefs['profile'];
    if (profile is Map && (profile['name']?.toString().trim() ?? '').isNotEmpty) {
      return profile['name'].toString().trim();
    }
    final email = widget.accountEmail;
    if (email != null && email.contains('@')) return email.split('@').first;
    return _lang('ضيف', 'Guest');
  }

  Future<void> _selectCurrency() async {
    if (!_editable) return;
    final value = await showDialog<String>(context: context,
      builder: (context) => SimpleDialog(
        title: Text(_lang('اختر العملة', 'Choose currency')),
        children: [for (final code in currencyCodes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, code),
            child: Text(code),
          ),
        ],
      ));
    if (value == null || !mounted || !_editable || value == _currencyCode) return;
    await _applyLedger(InstallmentLedger(
      entries: _entries, installments: _plans,
      customCategories: _customCategories,
      prefs: {..._prefs, 'currency': value},
      createdAt: _createdAt,
    ), _lang('تم تغيير رمز العملة بدون تحويل المبالغ.',
             'Currency label changed without converting amounts.'));
  }


  String _monthDisplay(DateTime month) => widget.isEnglish
      ? DateFormat('MMMM yyyy', 'en').format(month) : monthTitle(month);

  String _dateDisplay(DateTime date) => widget.isEnglish
      ? DateFormat('d MMM yyyy', 'en').format(date) : formattedDate(date);

  String _categoryName(String value) {
    if (!widget.isEnglish) return value;
    const builtIns = <String, String>{
      'مشتريات': 'Shopping',
      'مصاريف شحن': 'Shipping fees',
      'اشتراكات': 'Subscriptions',
      'كهرباء': 'Electricity',
      'مياه': 'Water',
      'مستلزمات بيت': 'Household',
      'مصاريف شخصية': 'Personal',
      'أقساط': 'Installments',
      'مطاعم': 'Restaurants',
      'صحة': 'Health',
      'مواصلات': 'Transport',
      'فواتير': 'Bills',
      'أخرى': 'Other',
      'راتب': 'Salary',
      'تحويل وارد': 'Incoming transfer',
      'إيداع': 'Deposit',
    };
    return builtIns[value] ?? value;
  }


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
      builder: (context) => InstallmentEditor(original: original, month: _month,
          isEnglish: widget.isEnglish),
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
                  '${_dateDisplay(entry.date)}'),
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
          original: original, customCategories: _customCategories,
          isEnglish: widget.isEnglish),
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
      final bytes = await MonthlyReportPdf.create(report,
          isEnglish: widget.isEnglish);
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
          isEnglish: widget.isEnglish,
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
      color: background,
      gradient: background == null
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xE22A557E), const Color(0xED14385D)]
                  : [const Color(0xF9FFFFFF), const Color(0xF0DDEDF9)],
            )
          : null,
      borderRadius: BorderRadius.circular(22),
      border: border ?? Border.all(color: _line, width: 0.8),
      boxShadow: [BoxShadow(
        color: widget.isDark
            ? const Color(0x50020D21) : const Color(0x225A80A3),
        blurRadius: 18, offset: const Offset(0, 7)),
      ],
    ),
    padding: padding ?? const EdgeInsets.all(16),
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
            tooltip: _lang('الشهر السابق', 'Previous month'),
            onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_month_outlined, color: _accent, size: 19),
              const SizedBox(width: 8),
              Flexible(child: Text(_monthDisplay(_month),
                key: const Key('current-month'),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700))),
            ],
          )),
          IconButton(
            key: const Key('next-month'),
            tooltip: _lang('الشهر التالي', 'Next month'),
            onPressed: () => setState(() => _month = shiftMonth(_month, 1)),
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    ),
  );

  Widget _hero(MonthTotals totals) => InkWell(
    key: const Key('total-card'),
    onTap: () => _goTo(1, filter: _Filter.withdrawal),
    borderRadius: BorderRadius.circular(26),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: widget.isDark
              ? [const Color(0xFF1F5782), const Color(0xFF0B2C50)]
              : [const Color(0xFF8FBFDF), const Color(0xFFD7EAFB)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _line, width: 0.9),
        boxShadow: [BoxShadow(
          color: widget.isDark
              ? const Color(0x66031933) : const Color(0x335A93C0),
          blurRadius: 22, offset: const Offset(0, 9)),
        ],
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_lang('مصروفاتك', 'Your expenses'),
              style: TextStyle(color: _ink,
                fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 9),
            Row(mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.ltr,
              children: [
                Flexible(child: Text(_money(totals.withdrawal),
                  key: const Key('total-deposit'),
                  textDirection: TextDirection.ltr,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _ink,
                    fontSize: 32, fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Text(_currencyCode, style: TextStyle(
                  color: _ink, fontSize: 14,
                  fontWeight: FontWeight.w700)),
              ]),
          ],
        )),
        const SizedBox(width: 8),
        Container(
          width: 64, height: 66,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _accent.withValues(alpha: 0.32),
              _accent.withValues(alpha: 0.08),
            ]),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: _accent.withValues(alpha: 0.38)),
          ),
          child: Icon(Icons.account_balance_wallet_rounded,
            color: _ink, size: 36),
        ),
      ]),
    ),
  );

  Widget _smallMetric({required String title, required String value,
      required IconData icon, required Color color, required VoidCallback onTap,
      Key? key}) => Expanded(child: InkWell(
    key: key,
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: _panel(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              height: 31, width: 31,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _mutedText,
                fontWeight: FontWeight.w700, fontSize: 11))),
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w800,
                fontSize: 19, color: _ink)),
          ),
          const SizedBox(height: 3),
          Text(_currencyCode, style: TextStyle(
            fontSize: 10, color: _mutedText)),
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
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color)),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_categoryName(entry.title), maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text('${formattedDate(entry.date)} · '
                  '${entry.source.isEmpty ? _lang('يدوي', 'Manual') : entry.source}'
                  '${entry.excluded ? _lang(' · مستبعدة', ' · excluded') : ''}',
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
      return _empty(emptyMessage ?? _lang('لا توجد معاملات مطابقة في هذا الشهر', 'No matching transactions this month'),
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
              overdue > 0 ? _lang('عندك ', 'You have ') + overdue.toString() + _lang(' قسط متأخر', ' overdue installments')
                  : today > 0 ? _lang('عندك ', 'You have ') + today.toString() + _lang(' قسط النهارده', ' due today')
                  : _lang('أقساط مستحقة قريبًا', 'Upcoming installment payments'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            )),
            TextButton(
              onPressed: () => _goTo(2),
              child: Text(_lang('عرض الأقساط', 'View installments'))),
          ]),
          for (final n in notices.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(n.plan.name + ': ' + _currency(n.plan.amount) +
                  ' · ' + (n.daysLeft < 0 ? _lang('متأخر', 'Overdue') :
                      n.daysLeft == 0 ? _lang('النهارده', 'Today') :
                      _lang('بعد ', 'In ') + n.daysLeft.toString() + _lang(' يوم', ' days')),
                style: TextStyle(color: _mutedText, fontSize: 12)),
            ),
          if (notices.length > 3)
            Text(_lang('وفيه ', 'Plus ') + (notices.length - 3).toString() + _lang(' قسط إضافي', ' more installments'),
              style: TextStyle(color: _mutedText, fontSize: 12)),
        ],
      )),
    );
  }

  Widget _home() {
    final totals = _summary.totals(_month);
    final recent = _summary.recent(_month);
    return ListView(
      key: const Key('home-page'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      children: [
        _hero(totals),
        const SizedBox(height: 7),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _smallMetric(key: const Key('withdrawal-card'), title: _lang('السحب', 'Expenses'),
            value: _money(totals.withdrawal), icon: Icons.north_east,
            color: _red, onTap: () => _goTo(1,
                filter: _Filter.withdrawal)),
          const SizedBox(width: 8),
          _smallMetric(title: _lang('الإيداع', 'Income'), value: _money(totals.deposit),
            icon: Icons.south_west, color: _blue,
            onTap: () => _goTo(1, filter: _Filter.deposit)),
          const SizedBox(width: 8),
          _smallMetric(title: _lang('المتبقي', 'Balance'), value: _money(totals.remaining),
            icon: Icons.radio_button_checked,
            color: totals.remaining < 0 ? _red : _green,
            onTap: () => _goTo(1)),
        ]),
        _monthPicker(),
        _dueNoticesPanel(),
        InkWell(
          key: const Key('category-expenses-action'),
          borderRadius: BorderRadius.circular(22),
          onTap: () => _goTo(3),
          child: _panel(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 11),
            child: Row(children: [
              Container(
                height: 39, width: 39,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.19),
                  shape: BoxShape.circle),
                child: Icon(Icons.pie_chart_outline, color: _accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_lang('المصروفات حسب التصنيف',
                       'Expenses by category'),
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(_lang('اعرض مصروفاتك حسب الفئات',
                      'Explore your spending categories'),
                    style: TextStyle(
                      fontSize: 11, color: _mutedText)),
                ],
              )),
              Icon(Icons.chevron_left, color: _accent),
            ]),
          ),
        ),
        _sectionTitle(_lang('المعاملات الأخيرة', 'Recent transactions'),
            action: _lang('عرض الكل ←', 'View all →'), onTap: () => _goTo(1)),
        _entryList(recent,
            emptyMessage: _lang('أضف أول معاملة', 'Add your first transaction')),
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
          _action(_lang('استيراد SMS', 'Import SMS'), Icons.sms_outlined,
              () => _importSmsFile()),
          _action(_lang('تقرير PDF', 'PDF report'), Icons.download,
              () => _exportMonthlyReport()),
          _action(_lang('معاملة يدوية', 'New transaction'), Icons.add,
              () => _editTransaction()),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 7, children: [
          _chip(_lang('الكل', 'All'), _Filter.all),
          _chip(_lang('↗ السحب', '↗ Expenses'), _Filter.withdrawal),
          _chip(_lang('↙ الإيداع', '↙ Income'), _Filter.deposit),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: _lang('بحث بالاسم أو المصدر أو النص...', 'Search by name, source or notes...'),
            border: const OutlineInputBorder(),
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
          _smallMetric(title: _lang('أقساط الشهر', 'Installments this month'),
              value: _money(summary.total), icon: Icons.calendar_month,
              color: _blue, onTap: () {}),
          const SizedBox(width: 9),
          _smallMetric(title: _lang('المتبقي دفعه', 'Remaining to pay'),
              value: _money(summary.remaining),
              icon: Icons.schedule_outlined,
              color: summary.remaining > 0 ? _red : _green,
              onTap: () {}),
        ]),
        const SizedBox(height: 16),
        _panel(
          background: _alt,
          child: Text(
            _lang('🔔 بنعرض الأقساط المستحقة عند فتح حساباتي. '
                'صدّر مواعيد الأقساط للتقويم وفعّل تنبيهاته '
                'علشان توصلك حتى لو حساباتي مقفول.',
                '🔔 Due installments appear when you open Hesabaty. '
                'Export them to your calendar and enable calendar alerts '
                'to get reminders while the app is closed.'),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        const SizedBox(height: 13),
        Wrap(spacing: 9, children: [
          _action(_lang('＋ إضافة قسط', '＋ Add installment'), Icons.add, () => _editInstallment()),
          _action(_lang('تصدير للتقويم', 'Export to calendar'), Icons.calendar_month_outlined,
              () => _exportCalendar()),
        ]),
        _sectionTitle(_lang('الأقساط المسجلة', 'Saved installments')),
        if (summary.plans.isEmpty)
          _empty(_lang('مفيش أقساط مسجلة للشهر ده، ابدأ بإضافة أول قسط', 'No installments scheduled this month'),
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
      DueStatus.paid => _lang('مدفوع', 'Paid'),
      DueStatus.overdue => _lang('متأخر', 'Overdue'),
      DueStatus.today => _lang('مستحق اليوم', 'Due today'),
      DueStatus.upcoming => _lang('منتظر الدفع', 'Awaiting payment'),
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
              Text(widget.isEnglish
                  ? 'Day ${plan.dueDay} each month · ${plan.count == 0 ? 'Ongoing' : '${plan.payments.length} of ${plan.count}'}'
                  : 'يوم ${plan.dueDay} من كل شهر · ${plan.count == 0 ? 'مستمر' : '${plan.payments.length} من ${plan.count}'}',
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
        Text('${_lang('الاستحقاق:', 'Due:')} ${_dateDisplay(plan.dueDate(_month))}',
            style: TextStyle(color: _mutedText, fontSize: 12)),
        const SizedBox(height: 9),
        Wrap(spacing: 8, runSpacing: 7, children: [
          if (!paid)
            _action(_lang('✓ تسجيل الدفع', '✓ Record payment'), Icons.check,
                () => _payInstallment(plan))
          else
            _action(_lang('إلغاء تسجيل الدفع', 'Undo payment'), Icons.undo,
                () => _undoInstallmentPayment(plan)),
          _action(_lang('تعديل', 'Edit'), Icons.edit_outlined,
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
        Text(_lang('التحليلات', 'Analytics'), style: const TextStyle(
          fontSize: 23, fontWeight: FontWeight.w800,
        )),
        Text(_lang('اعرف فلوسك راحت فين وقارن بين الشهور', 'Explore spending and compare months'),
            style: TextStyle(color: _mutedText, fontSize: 12)),
        _monthPicker(),
        _sectionTitle(_lang('حركة آخر 6 شهور', 'Last 6 months')),
        _panel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sixMonthChart(analysis),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _analyticsLegend(_lang('الإيداع', 'Income'), _accent),
              const SizedBox(width: 20),
              _analyticsLegend(_lang('السحب', 'Expenses'), _red),
            ]),
          ],
        )),
        _sectionTitle(_lang('المقارنة الشهرية', 'Monthly comparison')),
        _panel(child: Column(
          children: [
            _analyticsRow(_lang('سحب الشهر الحالي', 'Expenses this month'),
                _currency(comparison.current.withdrawal),
                valueColor: _red),
            Divider(color: _line),
            _analyticsRow(_lang('سحب الشهر السابق', 'Expenses last month'),
                _currency(comparison.previous.withdrawal)),
            Divider(color: _line),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.isEnglish ? comparison.describeEnglish(_money) : comparison.describe(_money),
                key: const Key('expense-comparison'),
                style: TextStyle(
                  color: _mutedText, height: 1.8, fontSize: 12,
                ),
              ),
            ),
          ],
        )),
        _sectionTitle(_lang('توزيع المصروفات', 'Spending breakdown')),
        if (categories.isEmpty)
          _empty(_lang('مفيش مصروفات للتحليل في الشهر ده', 'No expenses to analyze this month'),
              Icons.trending_down_outlined)
        else
          _panel(child: Column(
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text(_categoryName(categories[i].key),
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
        _sectionTitle(_lang('مؤشرات الشهر', 'Monthly indicators')),
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
                          title: _lang('الإيداع', 'Income'),
                        )),
                        const SizedBox(width: 3),
                        Flexible(child: _analyticsBar(
                          key: Key('month-$index-withdrawal'),
                          value: monthly[index].totals.withdrawal,
                          maxValue: maxValue,
                          color: _red,
                          month: monthly[index].month,
                          title: _lang('السحب', 'Expenses'),
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
        title: Text(_lang('تصدير نسخة احتياطية', 'Export backup')),
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
        widget.store is! LedgerStore ||
        !CloudRestorePolicy.mayRestoreOnLaunch(
          local: _currentLedger, savedCloudRevision: _cloudRevision,
        )) {
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      final remote = await CloudFinanceSync(Supabase.instance.client).fetch();
      if (!mounted || remote == null ||
          !CloudRestorePolicy.mayRestoreOnLaunch(
            local: _currentLedger, savedCloudRevision: _cloudRevision,
          )) {
        return;
      }
      // Don't trigger a replacement at all if the server is also empty.
      if (CloudRestorePolicy.isEmpty(remote.ledger)) return;
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
    if (!widget.cloudEnabled || _cloudBusy || !_editable || !mounted ||
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
          LedgerContent.equivalent(local, remote.ledger)) {
        await _rememberCloudRevision(remote.revision);
        if (mounted) {
          setState(() => _autoSyncStatus = 'البيانات على الجهاز والسحابة متطابقتين.');
        }
        return;
      }
      if (remote == null && local.entries.isEmpty &&
          local.installments.isEmpty && checkpoint == null) {
        if (mounted) {
          setState(() => _autoSyncStatus = 'مفيش بيانات محتاجة مزامنة.');
        }
        return;
      }
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
      final hasLocal = !CloudRestorePolicy.isEmpty(local);
      if (remote == null) {
        if (_cloudRevision != null) {
          _showCloudMessage('كانت فيه نسخة سحابية مرتبطة بالجهاز '
              'لكن دلوقتي مش موجودة. وقفنا الرفع لحماية الحساب؛ '
              'راجع السبب قبل إعادة إنشاء النسخة.');
          return;
        }
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

  static const _websiteHost = 'mohmoudtarek37-spec.github.io';

  Future<void> _openLegalResource(String page) async {
    final url = Uri.https(_websiteHost, '/smart-expenses/' + page);
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw const FormatException('Could not open legal URL');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذر فتح الصفحة. تقدر تزور ' + url.toString() +
            ' من أي متصفح.'),
        duration: const Duration(seconds: 10),
      ));
    }
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب حذف حساب حساباتي وبياناته'),
        content: const Text(
          'هنفتح صفحة مخصصة لطلب حذف حسابك والبيانات المرتبطة بيه. '
          'الطلب مش هيحذف الحساب فورًا، وممكن تحتاج تأكيد ملكيته. '
          'احتفظ بنسخة احتياطية لو عندك معاملات عايز تحتفظ بيها. '
          'لو عندك اشتراك Premium، راجع اشتراكات Google Play بشكل منفصل.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع')),
          FilledButton(
            key: const Key('confirm-deletion-request'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('فتح صفحة طلب الحذف')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _openLegalResource('delete-account.html');
    }
  }

  Future<void> _openAccountProfile() async {
    if (!_editable) return;
    final profile = _prefs['profile'] is Map
        ? Map<String, dynamic>.from(_prefs['profile'] as Map)
        : <String, dynamic>{};
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => AccountProfilePage(
        initial: profile,
        scope: widget.cloudEnabled
            ? (Supabase.instance.client.auth.currentUser?.id ?? 'guest')
            : 'guest',
        email: widget.accountEmail,
        isEnglish: widget.isEnglish,
      )),
    );
    if (updated == null || !mounted || !_editable) return;
    await _applyLedger(InstallmentLedger(
      entries: _entries,
      installments: _plans,
      customCategories: _customCategories,
      prefs: {..._prefs, 'profile': updated},
      createdAt: _createdAt,
    ), _lang('تم حفظ بيانات الحساب.', 'Account profile saved.'));
  }

  Future<void> _inviteFriends() async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: _lang('جرّب تطبيق حساباتي لإدارة مصروفاتك وأقساطك. '
            'تابع حساباتي على https://mohmoudtarek37-spec.github.io/smart-expenses/',
            'Try Hesabaty to manage expenses and installments. '
            'https://mohmoudtarek37-spec.github.io/smart-expenses/'),
      ));
    } catch (_) {
      if (mounted) {
        _showCloudMessage(_lang(
          'تعذر فتح مشاركة الرابط.', 'Could not open sharing.'));
      }
    }
  }

  /// Deleting financial data must not allow an older cloud snapshot to restore
  /// it. A signed-in user must be online and completely in sync to proceed.
  Future<void> _eraseAllData() async {
    if (!_editable || widget.store is! LedgerStore) return;
    final input = TextEditingController();
    final expected = widget.isEnglish ? 'DELETE' : 'حذف';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(_lang('مسح كل البيانات', 'Erase all data')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_lang(
              widget.cloudEnabled
                  ? 'ده هيمسح معاملات الحساب والأقساط والملف الشخصي من الجهاز '
                    'والنسخة السحابية بعد التأكد من تطابق النسختين. '
                    'حسابك نفسه هيفضل موجود. صدّر نسخة احتياطية الأول.'
                  : 'ده هيمسح معاملات الضيف والأقساط والملف الشخصي '
                    'والنسخ المحلية المرتبطة بيه. حسابك (إن وجد) مش هيتحذف. '
                    'صدّر نسخة احتياطية الأول.',
              widget.cloudEnabled
                  ? 'This removes the account ledger, installments and profile '
                    'from this device AND the cloud after checking for conflicts. '
                    'Your login remains. Export a backup first.'
                  : 'This removes guest transactions, installments, profile '
                    'and local restore copies. Export a backup first.',
            )),
            const SizedBox(height: 12),
            TextField(
              key: const Key('erase-confirm-text'),
              controller: input,
              onChanged: (_) => update(() {}),
              decoration: InputDecoration(
                labelText: _lang('اكتب «حذف» للتأكيد', 'Type DELETE to confirm'),
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_lang('إلغاء', 'Cancel'))),
            FilledButton(
              key: const Key('erase-confirm-button'),
              onPressed: input.text.trim() == expected
                  ? () => Navigator.pop(dialogContext, true) : null,
              child: Text(_lang('مسح نهائي', 'Erase permanently')),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (accepted != true || !mounted || !_editable) return;
    setState(() => _saving = true);
    try {
      final store = widget.store! as LedgerStore;
      final previous = _currentLedger;
      final empty = const InstallmentLedger(entries: [], installments: []);
      int? revision;
      if (widget.cloudEnabled) {
        final cloud = CloudFinanceSync(Supabase.instance.client);
        final remote = await cloud.fetch();
        if (!mounted) return;
        if (remote != null) {
          if (!LedgerContent.equivalent(remote.ledger, previous)) {
            throw const CloudConflict();
          }
          // Only the exact reviewed revision can be changed.
          revision = await cloud.push(empty,
              expectedRevision: remote.revision);
        } else if (_cloudRevision != null) {
          throw const CloudConflict();
        }
      }
      if (store is FullAccountDataResetStore) {
        await (store as FullAccountDataResetStore).clearAllLocalData();
      } else {
        await store.saveLedger(empty);
      }
      if (!mounted) return;
      setState(() {
        _entries = [];
        _plans = [];
        _customCategories = [];
        _prefs = {};
        _createdAt = '';
        _cloudRevision = null;
        _month = DateTime(DateTime.now().year, DateTime.now().month);
      });
      if (revision != null) {
        await _rememberCloudRevision(revision);
      }
      if (mounted) {
        _showCloudMessage(_lang(
          'تم مسح بيانات هذا الحساب. تسجيل الدخول نفسه لم يُحذف.',
          'Financial data erased. Your login account still exists.'));
      }
    } on CloudConflict {
      if (mounted) {
        _showCloudMessage(_lang(
          'النسخة السحابية مختلفة؛ وقفنا المسح لحماية بيانات جهاز تاني. '
          'راجع المزامنة أولًا.',
          'Cloud data differs. Erase stopped to protect changes on another device.'));
      }
    } catch (_) {
      if (mounted) {
        _showCloudMessage(_lang(
          'تعذر إكمال المسح؛ راجع الاتصال وحالة البيانات قبل المحاولة مجددًا.',
          'Could not finish erasing; check connectivity and cloud state.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _settingsHeading(String ar, String en) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
    child: Text(_lang(ar, en),
      style: TextStyle(color: _ink,
        fontSize: 16, fontWeight: FontWeight.w800)),
  );

  MemoryImage? _profilePhoto() {
    final profile = _prefs['profile'];
    if (profile is! Map) return null;
    final photo = profile['photo']?.toString() ?? '';
    if (photo.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(photo));
    } catch (_) {
      return null;
    }
  }

  Widget _settings() => ListView(
    key: const Key('settings-page'),
    padding: const EdgeInsets.all(18),
    children: [
      Text(_lang('الإعدادات', 'Settings'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      _settingsHeading('الحساب', 'Account'),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: ListTile(
        key: const Key('profile-settings'),
        leading: CircleAvatar(
          backgroundColor: _accent.withValues(alpha: 0.20),
          backgroundImage: _profilePhoto(),
          child: _profilePhoto() == null
              ? Icon(Icons.person_outline, color: _accent)
              : null,
        ),
        title: Text(_displayName),
        subtitle: Text(_displayName),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _accent.withValues(alpha: 0.27)),
            ),
            child: Text(_lang('الخطة المجانية', 'Free plan'),
              style: TextStyle(color: _accent, fontSize: 11,
                fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: _accent),
        ]),
        onTap: _editable ? _openAccountProfile : null,
      )),
      const SizedBox(height: 18),
      _settingsHeading('فلوسك', 'Your money'),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Column(children: [
        ListTile(
          key: const Key('currency-settings'),
          leading: const Icon(Icons.currency_exchange),
          title: Text(_lang('العملة', 'Currency')),
          subtitle: Text(_currencyCode),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editable ? _selectCurrency : null,
        ),
        ListTile(
          key: const Key('custom-categories'),
          leading: const Icon(Icons.category_outlined),
          title: Text(_lang('تخصيص الفئات', 'Customize categories')),
          subtitle: Text(_lang('الفئات الأساسية والتصنيفات المضافة',
              'Default and custom categories')),
        ),
        for (final category in _customCategories)
          ListTile(title: Text(category),
            trailing: IconButton(icon: const Icon(Icons.delete_outline),
              onPressed: _editable ? () => _removeCustomCategory(category) : null)),
        ListTile(
          key: const Key('add-custom-category'),
          leading: const Icon(Icons.add_circle_outline),
          title: Text(_lang('إضافة تصنيف جديد', 'Add category')),
          onTap: _editable ? _addCustomCategory : null,
        ),
      ])),
      const SizedBox(height: 18),
      _settingsHeading('التفضيلات والتنبيهات', 'Preferences & alerts'),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(_lang('تنبيهات الأقساط', 'Installment alerts')),
        subtitle: Text(_lang('مواعيد الاستحقاق وتقويم الهاتف',
            'Due dates and phone calendar')),
        onTap: () => _goTo(2),
      )),
      const SizedBox(height: 18),
      _settingsHeading('البيانات', 'Data'),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Column(children: [
        ListTile(
          key: const Key('invite-friends'),
          leading: const Icon(Icons.share_outlined),
          title: Text(_lang('ادعُ أصدقاءك', 'Invite friends')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _inviteFriends,
        ),
        ListTile(
          key: const Key('export-backup'),
          leading: const Icon(Icons.ios_share_outlined),
          title: Text(_lang('تصدير البيانات', 'Export data')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editable && widget.store is LedgerStore
              ? _exportBackup : null,
        ),
        ListTile(
          key: const Key('import-backup'),
          leading: const Icon(Icons.file_download_outlined),
          title: Text(_lang('استيراد المعاملات', 'Import transactions')),
          subtitle: Text(_lang('من نسخة حساباتي الاحتياطية',
              'From a Hesabaty backup file')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editable && widget.store is LedgerStore
              ? _importBackup : null,
        ),
        if (widget.store is BackupRestorableStore)
          ListTile(
            key: const Key('undo-backup-import'),
            leading: const Icon(Icons.restore),
            title: Text(_lang('التراجع عن آخر استيراد', 'Undo last import')),
            onTap: _editable ? _restoreBeforeLastImport : null,
          ),
        ListTile(
          key: const Key('erase-all-data'),
          leading: const Icon(Icons.delete_forever_outlined,
              color: Colors.red),
          title: Text(_lang('مسح كل البيانات', 'Erase all data'),
              style: const TextStyle(color: Colors.red)),
          trailing: const Icon(Icons.chevron_right, color: Colors.red),
          onTap: _editable ? _eraseAllData : null,
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(_lang(
            'ملفات التصدير غير مشفرة؛ احتفظ بيها في مكان آمن.',
            'Exported files are not encrypted. Keep them safe.'),
            style: TextStyle(color: _mutedText, fontSize: 12))),
      ])),
      if (widget.cloudEnabled && widget.guestStore is LedgerStore) ...[
        const SizedBox(height: 12),
        _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: ListTile(
          key: const Key('import-guest-data'),
          leading: const Icon(Icons.move_to_inbox_outlined),
          title: Text(_lang('نقل بيانات الضيف لحسابي',
              'Move guest data to my account')),
          onTap: _editable ? _importGuestData : null,
        )),
      ],
      const SizedBox(height: 18),
      _settingsHeading('الدعم', 'Support'),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Column(children: [
        ListTile(
          key: const Key('monthly-report-settings'),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(_lang('تقرير PDF الشهري', 'Monthly PDF report')),
          onTap: _exportMonthlyReport,
        ),
        ListTile(
          key: const Key('sms-import-settings'),
          leading: const Icon(Icons.sms_outlined),
          title: Text(_lang('استيراد رسائل SMS', 'Import SMS messages')),
          onTap: _importSmsFile,
        ),
        if (widget.cloudEnabled) ...[
          ListTile(
            key: const Key('premium-settings'),
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(_lang('حساباتي Premium', 'Hesabaty Premium')),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => PremiumPage(
                isEnglish: widget.isEnglish))),
          ),
          ListTile(
            key: const Key('sync-cloud'),
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(_lang('مزامنة الحساب', 'Sync account')),
            onTap: _editable ? _syncCloudNow : null,
          ),
        ],
        if (_autoSyncStatus.isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_autoSyncStatus,
              key: const Key('cloud-sync-status'),
              style: const TextStyle(fontSize: 12))),
        if (widget.cloudEnabled)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_cloudQuotaLabel(),
              style: const TextStyle(fontSize: 12))),
        ListTile(
          key: const Key('privacy-policy-link'),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(_lang('سياسة الخصوصية', 'Privacy policy')),
          onTap: () => _openLegalResource('privacy-policy.html'),
        ),
      ])),
      const SizedBox(height: 20),
      _panel(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Column(children: [
        if (widget.cloudEnabled)
          ListTile(
            key: const Key('logout-settings'),
            leading: const Icon(Icons.logout_outlined),
            title: Text(_lang('تسجيل الخروج', 'Sign out')),
            onTap: widget.onSignOut,
          )
        else
          ListTile(
            key: const Key('login-from-settings'),
            leading: const Icon(Icons.login_outlined),
            title: Text(_lang('تسجيل الدخول أو إنشاء حساب',
                'Sign in or create account')),
            onTap: widget.onOpenAuth,
          ),
        if (widget.cloudEnabled)
          ListTile(
            key: const Key('request-account-deletion'),
            leading: const Icon(Icons.person_remove_outlined,
                color: Colors.red),
            title: Text(_lang('حذف الحساب', 'Delete account'),
                style: const TextStyle(color: Colors.red)),
            subtitle: Text(_lang('فتح صفحة طلب حذف الحساب',
                'Open the account deletion request page')),
            onTap: _requestAccountDeletion,
          ),
      ])),
      const SizedBox(height: 16),
      Text(_lang('حساباتي 2.0 — نسخة تجريبية للتقييم.',
          'Hesabaty 2.0 — Preview for review.'),
          style: TextStyle(color: _mutedText, fontSize: 12)),
    ],
  );

  Widget _tab(String label, IconData icon, int index) => Expanded(
    child: InkWell(
      onTap: () => _goTo(index),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 32, width: 39,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: _selected == index
                  ? _accent.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
            child: Icon(icon, size: 22,
              color: _selected == index ? _ink : _mutedText),
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10,
              color: _selected == index ? _ink : _mutedText,
              fontWeight: _selected == index
                  ? FontWeight.w800 : FontWeight.w400)),
        ]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: _pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
        toolbarHeight: 58,
        leading: IconButton(
          key: const Key('settings-action'),
          tooltip: _selected == 4
              ? _lang('الرئيسية', 'Home')
              : _lang('الإعدادات', 'Settings'),
          onPressed: () => _goTo(_selected == 4 ? 0 : 4),
          icon: Icon(_selected == 4
              ? Icons.arrow_back_ios_new_rounded
              : Icons.settings_outlined),
        ),
        centerTitle: true,
        title: Text(_selected == 4
            ? _lang('الإعدادات', 'Settings')
            : _lang('مرحبًا $_displayName', 'Hi $_displayName'),
          key: const Key('personal-greeting'),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            key: const Key('language-action'),
            tooltip: 'Language / اللغة',
            onPressed: widget.onToggleLanguage,
            icon: Text(widget.isEnglish ? 'ع' : 'EN',
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800))),
          IconButton(
            key: const Key('theme-action'),
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDark
              ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (widget.store != null)
            Container(
              width: double.infinity,
              color: widget.isDark
                  ? const Color(0xFF214968)
                  : const Color(0xFFACCEE6),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Text(
                _loadError ?? (widget.cloudEnabled
                    ? _lang('نسخة اختبار: الحفظ المحلي والمزامنة السحابية قيد التحقق. احتفظ بنسخة احتياطية.', 'Preview: cloud sync is not fully verified; keep a backup.')
                    : _lang('نسخة تجريبية: معاملات الضيف محفوظة على هذا الجهاز فقط. احتفظ بنسخة احتياطية.', 'Preview: guest transactions are saved on this device only.')),
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
        foregroundColor: const Color(0xFF082B46),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        tooltip: _lang('إضافة معاملة جديدة', 'Add transaction'),
        child: const Icon(Icons.add, size: 30),
      ),
    ));
  }
}
