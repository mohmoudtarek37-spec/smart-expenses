import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/transaction_store.dart';
import 'package:hesabaty/main.dart';
import 'package:hesabaty/screens/finance_shell.dart';

void main() {
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
