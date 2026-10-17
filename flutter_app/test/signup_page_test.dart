import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/screens/signup_page.dart';

Future<void> _tapVisible(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creating an account is a separate screen, not an immediate API call',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => SignUpPage(
              register: (email, password) async {
                calls++;
                return true;
              },
            ),
          )),
          child: const Text('إنشاء حساب جديد'),
        )),
      ),
    ));
    await tester.tap(find.text('إنشاء حساب جديد'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-page')), findsOneWidget);
    expect(find.byKey(const Key('signup-email')), findsOneWidget);
    expect(find.byKey(const Key('signup-name')), findsOneWidget);
    expect(find.byKey(const Key('signup-password')), findsOneWidget);
    expect(find.byKey(const Key('signup-confirm-password')), findsOneWidget);
    expect(calls, 0);

    await _tapVisible(tester, 'signup-submit');
    expect(calls, 0);
    expect(find.textContaining('بريدك الإلكتروني كامل'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('signup-email')), 'example@gmail.com');
    await tester.enterText(
        find.byKey(const Key('signup-name')), 'محمود');
    await tester.enterText(
        find.byKey(const Key('signup-password')), 'strong-password-123');
    await tester.enterText(
        find.byKey(const Key('signup-confirm-password')), 'different');
    await _tapVisible(tester, 'signup-submit');
    expect(calls, 0);
    expect(find.textContaining('مش مطابق'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('signup-confirm-password')),
        'strong-password-123');
    await _tapVisible(tester, 'signup-submit');
    expect(calls, 1);
    expect(find.byKey(const Key('signup-page')), findsNothing);
  });

  testWidgets('no session keeps user on signup page with clear server guidance',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: SignUpPage(
        initialEmail: 'testing@example.com',
        register: (email, password) async {
          attempts++;
          return false;
        },
      ),
    ));
    await tester.enterText(
        find.byKey(const Key('signup-name')), 'محمود');
    await tester.enterText(
        find.byKey(const Key('signup-password')), 'password-is-long');
    await tester.enterText(
        find.byKey(const Key('signup-confirm-password')),
        'password-is-long');
    await _tapVisible(tester, 'signup-submit');
    expect(attempts, 1);
    expect(find.byKey(const Key('signup-page')), findsOneWidget);
    expect(find.textContaining('Confirm Email'), findsOneWidget);
  });

  testWidgets('back to login returns without creating an account',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => SignUpPage(
            register: (email, password) async {
              calls++;
              return true;
            },
          ),
        )),
        child: const Text('ابدأ'),
      ),
    )));
    await tester.tap(find.text('ابدأ'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, 'signup-back');
    expect(find.byKey(const Key('signup-page')), findsNothing);
    expect(calls, 0);
  });
}
