import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';
import 'package:hesabaty/finance/transaction_store.dart';
import 'package:hesabaty/main.dart';
import 'package:hesabaty/screens/finance_shell.dart';

void main() {

  testWidgets('language control changes navigation and can return to Arabic',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    await tester.pumpAndSettle();
    expect(find.text('الرئيسية'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-action')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-action')));
    await tester.pumpAndSettle();
    expect(find.text('الرئيسية'), findsOneWidget);
  });

  testWidgets('English mode translates finance content and transaction editor',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      home: Directionality(textDirection: TextDirection.ltr,
        child: FinanceShell(
          isEnglish: true, store: _WidgetLedgerStore(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Total income'), findsOneWidget);
    expect(find.text('Spending ratio'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Expenses by category'), 180,
      scrollable: find.descendant(
        of: find.byKey(const Key('home-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expenses by category'), findsOneWidget);
    await tester.tap(find.text('Transactions').last);
    await tester.pumpAndSettle();
    expect(find.text('All income and expense transactions'), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('Add a transaction'), findsOneWidget);
    expect(find.text('Amount (EGP)'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('account profile saves an optional username without login',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _WidgetLedgerStore();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
        child: FinanceShell(store: store, onOpenAuth: () {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-account-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-photo')), findsOneWidget);
    expect(find.byKey(const Key('profile-phone')), findsOneWidget);
    expect(find.byKey(const Key('profile-birthday')), findsOneWidget);
    expect(find.byKey(const Key('profile-gender')), findsOneWidget);
    expect(find.byKey(const Key('profile-biometric')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile-name')), 'Test user');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect((store.ledger.prefs['profile'] as Map)['name'], 'Test user');
  });

  testWidgets('erase all data is behind an explicit typed confirmation',
      (WidgetTester tester) async {
    final store = _WidgetLedgerStore();
    store.ledger = InstallmentLedger(entries: [
      FinanceEntry(id: 'safe', type: EntryType.deposit, amount: 150,
          date: DateTime.now(), category: 'Salary'),
    ], installments: const []);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
        child: FinanceShell(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-action')));
    await tester.pumpAndSettle();
    final erase = find.byKey(const Key('erase-all-data'));
    await tester.scrollUntilVisible(
      erase, 180,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(erase);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('erase-confirm-button')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('erase-confirm-button')));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(store.ledger.entries.single.id, 'safe');
  });

  testWidgets('HTML-style home and 4 tabs plus add action render',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    expect(find.text('أهلًا بيك 👋'), findsOneWidget);
    expect(find.text('فلوسك في مكان واحد'), findsOneWidget);
    expect(find.byKey(const Key('total-card')), findsOneWidget);
    expect(find.byKey(const Key('add-transaction')), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المعاملات'), findsOneWidget);
    expect(find.text('الأقساط'), findsWidgets);
    expect(find.text('التحليلات'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('guest opens dashboard, with optional login only in Settings',
      (WidgetTester tester) async {
    final guest = _WidgetLedgerStore();
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FinanceShell(
          key: const ValueKey('guest-shell'),
          store: guest,
          onOpenAuth: () => openCount++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-page')), findsOneWidget);
    expect(find.byKey(const Key('add-transaction')), findsOneWidget);
    expect(find.byKey(const Key('login-from-settings')), findsNothing);
    expect(find.text('أهلًا بيك 👋'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-account-status')), findsOneWidget);
    expect(find.textContaining('مش بتتنقل للحساب تلقائيًا'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('login-from-settings')), 180,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-from-settings')));
    expect(openCount, 1);
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets('signed-in account shows sign out, not guest login',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FinanceShell(
          key: const ValueKey('user-test'),
          store: _WidgetLedgerStore(),
          cloudEnabled: true,
          accountEmail: 'test@example.com',
          onSignOut: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-status')), findsOneWidget);
    expect(find.text('test@example.com'), findsWidgets);
    expect(find.byKey(const Key('login-from-settings')), findsNothing);
    final settingsScroll = find.descendant(
      of: find.byKey(const Key('settings-page')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('request-account-deletion')), 200,
      scrollable: settingsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-account-deletion')), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy-policy-link')), -140,
      scrollable: settingsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-policy-link')), findsOneWidget);
  });

  testWidgets('analytics shows 6-month bars, category and monthly comparison',
      (WidgetTester tester) async {
    final today = DateTime.now();
    final previous = DateTime(today.year, today.month - 1, 9);
    final entries = [
      FinanceEntry(id: 'income', type: EntryType.deposit, amount: 1000,
        date: DateTime(today.year, today.month, 2), category: 'راتب'),
      FinanceEntry(id: 'expense', type: EntryType.withdrawal, amount: 200,
        date: DateTime(today.year, today.month, 3), category: 'مطاعم'),
      FinanceEntry(id: 'old', type: EntryType.withdrawal, amount: 100,
        date: previous, category: 'مواصلات'),
      FinanceEntry(id: 'excluded', type: EntryType.withdrawal, amount: 700,
        date: DateTime(today.year, today.month, 4),
        category: 'صحة', excluded: true),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
        child: FinanceShell(entries: entries)),
    ));
    await tester.tap(find.text('التحليلات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analytics-page')), findsOneWidget);
    expect(find.byKey(const Key('six-month-chart')), findsOneWidget);
    expect(find.byKey(const Key('month-0-deposit')), findsOneWidget);
    expect(find.byKey(const Key('month-5-withdrawal')), findsOneWidget);
    expect(find.text('حركة آخر 6 شهور'), findsOneWidget);
    expect(find.text('المقارنة الشهرية'), findsOneWidget);
    final analyticsScroll = find.descendant(
      of: find.byKey(const Key('analytics-page')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('expense-comparison')), 170,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('أعلى من الشهر السابق'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('expense-category-مطاعم')), 150,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-category-مطاعم')), findsOneWidget);
    expect(find.byKey(const Key('expense-category-صحة')), findsNothing);
  });

  testWidgets('empty analytics avoids divide by zero and shows no chart data',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    await tester.tap(find.text('التحليلات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('six-month-chart')), findsOneWidget);
    final analyticsScroll = find.descendant(
      of: find.byKey(const Key('analytics-page')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('expense-comparison')), 170,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('مفيش مصروفات مسجلة في الشهرين.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('analytics-spending-share')), 170,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('مفيش مصروفات للتحليل في الشهر ده'), findsOneWidget);
    expect(find.byKey(const Key('analytics-spending-share')), findsOneWidget);
  });

  testWidgets('month selector updates its label',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    final monthText = tester.widget<Text>(
        find.byKey(const Key('current-month')));
    final original = monthText.data;
    await tester.drag(find.byKey(const Key('home-page')), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('previous-month')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('current-month'))).data,
        isNot(original));
  });

  testWidgets('supplied finance entries populate home summaries',
      (WidgetTester tester) async {
    final date = DateTime.now();
    final entries = [
      FinanceEntry(id: 'one', type: EntryType.deposit, amount: 1000,
          date: DateTime(date.year, date.month, 1), category: 'راتب'),
      FinanceEntry(id: 'two', type: EntryType.withdrawal, amount: 200,
          date: DateTime(date.year, date.month, 2), category: 'مطاعم'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FinanceShell(entries: entries),
      ),
    ));
    expect(find.text('1,000'), findsWidgets);
    expect(find.text('200'), findsWidgets);
    expect(find.text('800'), findsWidgets);
    await tester.tap(find.text('المعاملات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transactions-page')), findsOneWidget);
    expect(find.text('راتب'), findsWidgets);
    expect(find.text('مطاعم'), findsWidgets);
  });

  testWidgets('new transaction is saved and immediately updates month totals',
      (WidgetTester tester) async {
    final store = _WidgetStore();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
          child: FinanceShell(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('إضافة معاملة جديدة'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('transaction-amount')), '275.50');
    await tester.ensureVisible(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    expect(store.entries, hasLength(1));
    expect(store.entries.single.amount, 275.50);
    expect(store.entries.single.type, EntryType.withdrawal);
    expect(find.text('275.5'), findsWidgets);
  });

  testWidgets('failed storage write never updates visible account balance',
      (WidgetTester tester) async {
    final store = _WidgetStore(failOnSave: true);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
          child: FinanceShell(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-transaction')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('transaction-amount')), '120');
    await tester.ensureVisible(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.textContaining('فشل حفظ التغيير'), findsOneWidget);
    expect(find.text('120'), findsNothing);
  });

  testWidgets('edits and deletes one existing transaction safely',
      (WidgetTester tester) async {
    final today = DateTime.now();
    final store = _WidgetStore();
    store.entries = [
      FinanceEntry(id: 'existing', type: EntryType.withdrawal,
        amount: 55, date: DateTime(today.year, today.month, 2),
        category: 'مطاعم', note: 'غداء'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
          child: FinanceShell(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المعاملات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('غداء'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('transaction-amount')), '82.25');
    await tester.ensureVisible(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-transaction')));
    await tester.pumpAndSettle();
    expect(store.entries, hasLength(1));
    expect(store.entries.single.id, 'existing');
    expect(store.entries.single.amount, 82.25);
    await tester.tap(find.text('غداء'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('حذف المعاملة؟'), findsOneWidget);
    await tester.tap(find.text('تأكيد الحذف'));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.text('لا توجد معاملات مطابقة في هذا الشهر'), findsOneWidget);
  });

  testWidgets('installment editor and payment update atomic local ledger',
      (WidgetTester tester) async {
    final store = _WidgetLedgerStore();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl,
          child: FinanceShell(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأقساط').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('installments-page')), findsOneWidget);
    await tester.tap(find.text('＋ إضافة قسط'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('installment-name')),
        'قسط الموبايل');
    await tester.enterText(find.byKey(const Key('installment-amount')), '250');
    await tester.ensureVisible(find.byKey(const Key('save-installment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-installment')));
    await tester.pumpAndSettle();
    expect(store.ledger.installments, hasLength(1));
    expect(store.ledger.installments.single.amount, 250);
    await tester.scrollUntilVisible(
      find.text('✓ تسجيل الدفع'), 180,
      scrollable: find.descendant(
        of: find.byKey(const Key('installments-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('✓ تسجيل الدفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-new-withdrawal')));
    await tester.pumpAndSettle();
    expect(store.ledger.entries, hasLength(1));
    expect(store.ledger.entries.single.amount, 250);
    expect(store.ledger.installments.single.payments, hasLength(1));
    expect(InstallmentMonthSummary(store.ledger.installments, DateTime.now())
        .remaining, 0);
  });

  testWidgets('preview prevents accidentally creating fake user records',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    await tester.tap(find.byKey(const Key('add-transaction')));
    await tester.pump();
    expect(find.textContaining('المعاينة لا تحفظ بيانات'), findsOneWidget);
  });
}

class _WidgetStore implements TransactionStore {
  _WidgetStore({this.failOnSave = false});
  final bool failOnSave;
  List<FinanceEntry> entries = [];

  @override
  Future<List<FinanceEntry>> load() async => List.of(entries);

  @override
  Future<void> save(List<FinanceEntry> next) async {
    if (failOnSave) throw StateError('simulated disk write failure');
    entries = List.of(next);
  }
}

class _WidgetLedgerStore implements LedgerStore {
  InstallmentLedger ledger =
      const InstallmentLedger(entries: [], installments: []);

  @override
  Future<List<FinanceEntry>> load() async => List.of(ledger.entries);

  @override
  Future<InstallmentLedger> loadLedger() async => ledger;

  @override
  Future<void> save(List<FinanceEntry> entries) async {
    ledger = InstallmentLedger(
        entries: entries, installments: ledger.installments);
  }

  @override
  Future<void> saveLedger(InstallmentLedger next) async => ledger = next;
}
