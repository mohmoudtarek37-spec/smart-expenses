import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/auth/auth_feedback.dart';

void main() {
  test('validates email input before calling signup', () {
    expect(AuthFeedback.validEmail('user@example.com'), isTrue);
    expect(AuthFeedback.validEmail(' user@example.com '), isTrue);
    expect(AuthFeedback.validEmail('broken'), isFalse);
    expect(AuthFeedback.validEmail('example@'), isFalse);
    expect(AuthFeedback.validEmail('a @example.com'), isFalse);
  });

  test('shows clear message when signup is disabled', () {
    expect(AuthFeedback.serverError('Signups not allowed for this instance'),
        contains('متوقف'));
  });

  test('explains Supabase email confirmation rate limiting', () {
    expect(AuthFeedback.serverError('Email rate limit exceeded'),
        contains('حد رسائل التأكيد'));
  });

  test('explains mailer and password failures', () {
    expect(AuthFeedback.serverError('Error sending confirmation email'),
        contains('إرسال'));
    expect(AuthFeedback.serverError('Password should contain at least one number'),
        contains('كلمة المرور'));
  });

  test('explains unauthorized Supabase email destinations and confirmation', () {
    expect(AuthFeedback.serverError('Email address not authorized'),
        contains('SMTP'));
    expect(AuthFeedback.serverError('email_not_confirmed'),
        contains('تأكيد'));
  });

  test('gives fallback with real backend failure text', () {
    expect(AuthFeedback.serverError('Server rejected request, code 123'),
        contains('code 123'));
  });

  test('helps users distinguish network failures', () {
    expect(AuthFeedback.serverError('Failed host lookup'),
        contains('يتصل بالسيرفر'));
  });
}
