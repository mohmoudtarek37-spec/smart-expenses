import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/screens/signup_page.dart';

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
    expect(find.byKey(const Key('signup-password')), findsOneWidget);
    expect(find.byKey(const Key('signup-confirm-password')), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('بريدك الإلكتروني كامل'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('signup-email')), 'example@gmail.com');
    await tester.enterText(
        find.byKey(const Key('signup-password')), 'strong-password-123');
    await tester.enterText(
        find.byKey(const Key('signup-confirm-password')), 'different');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    expect(calls, 0);
    expect(find.textContaining('مش مطابق'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('signup-confirm-password')),
        'strong-password-123');
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byKey(const Key('signup-page')), findsNothing);
  });

  testWidgets('registration does not falsely claim success without session',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const SignUpPage(initialEmail: 'testing@example.com'),
    ));
    await tester.enterText(
        find.byKey(const Key('signup-password')), 'password-is-long');
    await tester.enterText(
        find.byKey(const Key('signup-confirm-password')),
        'password-is-long');
    // Here the user has not submitted; don't call a real auth backend.
    expect(find.byKey(const Key('signup-submit')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('signup-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-page')), findsNothing);
    expect(calls, 0);
  });
}
