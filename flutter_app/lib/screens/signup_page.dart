import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_feedback.dart';

/// Separate registration route. Opening this page never creates an account;
/// only the final explicit submission calls Supabase Auth.
class SignUpPage extends StatefulWidget {
  const SignUpPage({
    super.key,
    this.initialEmail = '',
    this.isEnglish = false,
    this.register,
  });

  final String initialEmail;
  final bool isEnglish;

  /// Injectable for UI tests. True means the server issued an active session.
  final Future<bool> Function(String email, String password)? register;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  late final TextEditingController _email;
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String _feedback = '';

  String _tr(String arabic, String english) =>
      widget.isEnglish ? english : arabic;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<bool> _registerOnSupabase(String email, String password) async {
    final response = await Supabase.instance.client.auth.signUp(
      email: email, password: password,
      data: {'full_name': _name.text.trim()},
    ).timeout(const Duration(seconds: 25));
    if (response.user == null) {
      throw StateError('The server did not create an account');
    }
    return response.session != null;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final email = _email.text.trim();
    final password = _password.text;
    final fullName = _name.text.trim();
    if (!AuthFeedback.validEmail(email)) {
      setState(() => _feedback = _tr(
        'اكتب بريدك الإلكتروني كامل، زي name@gmail.com.',
        'Enter your complete email, such as name@gmail.com.',
      ));
      return;
    }
    if (fullName.length < 2 || fullName.length > 60) {
      setState(() => _feedback = _tr(
        'اكتب اسمك (من حرفين لحد 60 حرف) علشان يظهر في حسابك.',
        'Enter your name (2–60 characters) for your profile.',
      ));
      return;
    }
    if (password.length < 8) {
      setState(() => _feedback = _tr(
        'كلمة المرور لازم تكون 8 حروف على الأقل.',
        'Your password must be at least 8 characters.',
      ));
      return;
    }
    if (_confirmation.text != password) {
      setState(() => _feedback = _tr(
        'تأكيد كلمة المرور مش مطابق. اكتب نفس الباسورد مرتين.',
        'Passwords do not match. Enter the same password twice.',
      ));
      return;
    }

    setState(() {
      _submitting = true;
      _feedback = '';
    });
    try {
      final active = await (widget.register ?? _registerOnSupabase)(
        email, password);
      if (!mounted) return;
      if (active) {
        // Close both signup and sign-in routes. The AuthGate displays the
        // account's finance shell after the signed-in event.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() => _feedback = _tr(
          'السيرفر لسه بيطلب تأكيد الإيميل. '
          'راجع إعداد Confirm Email في Supabase قبل إعادة المحاولة.',
          'The server still requires email confirmation. '
          'Check Confirm Email in Supabase before retrying.',
        ));
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _feedback = AuthFeedback.serverError(error.message));
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _feedback = _tr(
          'السيرفر اتأخر. جرّب تسجيل الدخول الأول قبل إعادة إنشاء الحساب.',
          'The server timed out. Try signing in before registering again.',
        ));
      }
    } on SocketException {
      if (mounted) {
        setState(() => _feedback = _tr(
          'مفيش اتصال بالسيرفر. راجع الإنترنت وحاول تاني.',
          'Cannot reach the server. Check your internet connection.',
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _feedback = _tr(
          'حصل خطأ أثناء إنشاء الحساب. جرّب مرة تانية.',
          'Could not create your account. Please try again.',
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_tr('إنشاء حساب جديد', 'Create account')),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          key: const Key('signup-page'),
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.person_add_alt_1_outlined, size: 62),
                  const SizedBox(height: 12),
                  Text(
                    _tr('حسابك الجديد في حساباتي', 'Your new Hesabaty account'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'املا بياناتك واضغط إنشاء الحساب. '
                      'مش هنطلب منك رسالة تفعيل.',
                      'Fill in the details and create your account. '
                      'No confirmation email is required.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('signup-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    autofillHints: const [AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: _tr('الاسم', 'Your name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('signup-email'),
                    controller: _email,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: _tr('البريد الإلكتروني', 'Email address'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('signup-password'),
                    controller: _password,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: _tr('كلمة المرور', 'Password'),
                      helperText: _tr('8 حروف على الأقل', 'At least 8 characters'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _tr('إظهار أو إخفاء كلمة المرور', 'Show or hide password'),
                        onPressed: () => setState(() =>
                            _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('signup-confirm-password'),
                    controller: _confirmation,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: _tr('تأكيد كلمة المرور', 'Confirm password'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_feedback.isNotEmpty)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _feedback,
                          key: const Key('signup-feedback'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('signup-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: Text(_tr('إنشاء الحساب', 'Create my account')),
                  ),
                  if (_submitting) const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('signup-back'),
                    onPressed: _submitting
                        ? null : () => Navigator.of(context).maybePop(),
                    child: Text(_tr('عندي حساب بالفعل — تسجيل الدخول',
                        'Already have an account? Sign in')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
