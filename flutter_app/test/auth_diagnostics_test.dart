import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/auth/server_diagnostics.dart';

void main() {
  test('parses public Supabase Auth provider capabilities', () {
    final result = AuthServerDiagnostics.fromPublicSettings({
      'disable_signup': false,
      'external': {'email': true, 'google': false},
    });
    expect(result.reachable, isTrue);
    expect(result.signupAllowed, isTrue);
    expect(result.emailEnabled, isTrue);
    expect(result.googleEnabled, isFalse);
    expect(result.humanMessage, contains('مش مفعّل'));
  });

  test('warns when email registration disabled', () {
    final result = AuthServerDiagnostics.fromPublicSettings({
      'disable_signup': true, 'external': {'email': true},
    });
    expect(result.signupAllowed, isFalse);
    expect(result.humanMessage, contains('مانعة إنشاء'));
  });

  test('health response never proves SMTP is working', () {
    const result = AuthServerDiagnostics(reachable: true);
    expect(result.humanMessage, contains('لا يؤكد'));
    const offline = AuthServerDiagnostics(reachable: false);
    expect(offline.humanMessage, contains('مش قادر'));
  });
}
