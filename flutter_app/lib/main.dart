import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/finance_shell.dart';
import 'auth/auth_feedback.dart';
import 'finance/transaction_store.dart';

const _backendUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _accent = Color(0xFFD4A600);
const _requireAccount = bool.fromEnvironment('REQUIRE_ACCOUNT',
    defaultValue: false);
const _mobileAuthCallback = 'io.github.mohmoudtarek37spec.hesabaty://auth-callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const configured = _backendUrl != '' && _publishableKey != '';
  if (configured) {
    await Supabase.initialize(
      url: _backendUrl,
      publishableKey: _publishableKey,
    );
  }
  runApp(HesabatyApp(
    backendConfigured: configured,
    guestStore: EncryptedTransactionStore(accountScope: 'guest'),
  ));
}

class HesabatyApp extends StatefulWidget {
  const HesabatyApp({super.key, this.backendConfigured = false,
      this.guestStore});

  final bool backendConfigured;
  final TransactionStore? guestStore;

  @override
  State<HesabatyApp> createState() => _HesabatyAppState();
}

class _HesabatyAppState extends State<HesabatyApp> {
  bool _isDark = false;

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حساباتي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: _accent,
          surface: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFE55D),
          surface: Color(0xFF1B1C26),
        ),
      ),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: widget.backendConfigured
            ? _AuthGate(
                guestStore: widget.guestStore,
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
              )
            : FinanceShell(
                key: const ValueKey('guest-shell'),
                store: widget.guestStore,
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
              ),
      ),
    );
  }
}

/// The app always opens to the dashboard. Accounts are an opt-in
/// enhancement offered from Settings, never a launch prerequisite.
class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.isDark,
    required this.onToggleTheme,
    this.guestStore,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final TransactionStore? guestStore;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  bool _openingRecovery = false;
  late final TransactionStore _guestStore;

  @override
  void initState() {
    super.initState();
    _guestStore = widget.guestStore ??
        EncryptedTransactionStore(accountScope: 'guest');
    _subscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((data) {
      if (!mounted) return;
      setState(() {});
      if (data.event == AuthChangeEvent.passwordRecovery &&
          !_openingRecovery) {
        _openingRecovery = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => const _PasswordRecoveryPage(),
          ));
          _openingRecovery = false;
        });
      }
    });
  }

  Future<void> _showSignIn() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => const _SignInPage(),
    ));
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تسجيل الخروج. حاول مرة تانية.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تسجيل الخروج. تأكد من الاتصال وجرب مرة تانية.'),
      ));
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final signedIn = user != null;
    // Stable keys force FinanceShell to unload account-specific records and
    // reopen the correct encrypted store whenever the user changes.
    if (_requireAccount && !signedIn) {
      return const _SignInPage(allowGuest: false);
    }
    return FinanceShell(
      key: ValueKey(signedIn ? 'user_${user.id}' : 'guest-shell'),
      store: signedIn
          ? EncryptedTransactionStore(accountScope: user.id)
          : _guestStore,
      cloudEnabled: signedIn,
      onOpenAuth: signedIn ? null : _showSignIn,
      accountEmail: signedIn ? user.email : null,
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
      onSignOut: signedIn ? _signOut : null,
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage({this.allowGuest = true});

  final bool allowGuest;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  StreamSubscription<AuthState>? _loginSubscription;
  bool _busy = false;
  bool _pendingConfirmation = false;
  String _status = '';
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loginSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((data) {
      if (mounted && data.event == AuthChangeEvent.signedIn &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _loginSubscription?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authenticate({required bool register}) async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (!AuthFeedback.validEmail(email)) {
      setState(() {
        _statusIsError = true;
        _status = 'راجع البريد الإلكتروني: لازم يكون بالشكل name@example.com';
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _statusIsError = true;
        _status = 'كلمة المرور لازم تكون 6 حروف على الأقل '
            '(والأفضل 8 حروف أو أكتر).';
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = register
          ? 'جاري إرسال طلب إنشاء الحساب للسيرفر...'
          : 'جاري تسجيل الدخول...';
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (register) {
        final result = await auth.signUp(
          email: email,
          password: password,
        ).timeout(const Duration(seconds: 25));
        if (!mounted) return;
        if (result.user == null) {
          setState(() {
            _statusIsError = true;
            _status = 'السيرفر ما رجّعش تأكيد إنشاء الحساب. '
                'متعيدش التسجيل بنفس البيانات قبل ما تراجع بريدك.';
          });
          return;
        }
        setState(() {
          _statusIsError = false;
          _pendingConfirmation = result.session == null;
          _status = result.session == null
              ? 'طلب إنشاء الحساب اتقبل. افتح إيميلك واضغط على رابط '
                  'التأكيد، وشوف Spam لو مش لاقي الرسالة، '
                  'وبعدها ارجع وسجل دخول.'
              : 'تم إنشاء الحساب وتسجيل الدخول بنجاح.';
        });
        if (result.session != null && mounted) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        }
      } else {
        await auth.signInWithPassword(
          email: email, password: password,
        ).timeout(const Duration(seconds: 25));
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = 'السيرفر اتأخر في الرد. ممكن يكون الطلب وصل؛ '
              'راجع إيميلك قبل ما تعيد المحاولة، '
              'واتأكد من اتصال الإنترنت.';
        });
      }
    } on SocketException {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = 'التطبيق مش قادر يوصل لسيرفر حساباتي. '
              'راجع الإنترنت وجرب شبكة تانية.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = AuthFeedback.serverError(error.message);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = 'حصل خطأ غير متوقع أثناء الاتصال '
              '(${error.runtimeType}). جرب مرة تانية أو ابعت صورة الرسالة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'جاري فتح تسجيل الدخول بحساب Google...';
    });
    try {
      final opened = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google, redirectTo: _mobileAuthCallback,
      );
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _statusIsError = true;
          _status = 'تعذر فتح تسجيل الدخول بجوجل. راجع إعدادات Google في Supabase.';
        });
      } else {
        setState(() {
          _status = 'كمّل الموافقة في متصفح Google. '
              'هترجع لحساباتي بعد تسجيل الدخول.';
        });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = AuthFeedback.serverError(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'Google Login محتاج تفعيل Google OAuth وروابط الرجوع في Supabase.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverPassword() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!AuthFeedback.validEmail(email)) {
      setState(() {
        _statusIsError = true;
        _status = 'اكتب بريدك الإلكتروني الصحيح علشان نبعث رابط الاستعادة.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'جاري طلب رسالة استعادة كلمة المرور...';
    });
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(email, redirectTo: _mobileAuthCallback)
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _status = 'لو الإيميل مربوط بحساب صالح، هتوصلك رسالة استعادة. '
            'راجع البريد وSpam، وما تشاركش رابط الاستعادة مع أي حد.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = AuthFeedback.serverError(e.message);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'السيرفر اتأخر في الاستجابة. راجع بريدك قبل إعادة المحاولة.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'تعذر طلب الاستعادة. تأكد من الإنترنت وخدمة الإيميل.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!AuthFeedback.validEmail(email)) {
      setState(() {
        _statusIsError = true;
        _status = 'اكتب بريدًا إلكترونيًا صحيحًا لإعادة إرسال التأكيد.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'جاري طلب رسالة تأكيد جديدة...';
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      ).timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _pendingConfirmation = true;
        _status = 'تم قبول طلب إعادة إرسال التأكيد. راجع البريد وSpam. '
            'لو الرسالة ما وصلتش، محتاجين نراجع إعدادات البريد في Supabase.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = AuthFeedback.serverError(error.message);
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'السيرفر اتأخر. راجع البريد قبل ما تعيد الطلب.';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'تعذر الوصول إلى Supabase. راجع الإنترنت.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = 'تعذر إرسال التأكيد. حاول مرة أخرى أو راجع إعدادات البريد.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحساب والتسجيل'),
        leading: widget.allowGuest ? IconButton(
          key: const Key('close-auth'),
          tooltip: 'الرجوع للتطبيق',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ) : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 64, color: _accent),
                const SizedBox(height: 14),
                Text('حساباتي', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text(widget.allowGuest
                    ? 'التسجيل اختياري في نسخة المعاينة. بيانات الضيف على الجهاز.'
                    : 'أنشئ حساب أو سجّل الدخول لاستخدام حساباتي وحفظ بياناتك بأمان.',
                    textAlign: TextAlign.center),
                if (_status.isNotEmpty)
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const Key('auth-status'),
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _statusIsError
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _statusIsError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                TextField(
                  key: const Key('auth-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('auth-password'),
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                      labelText: 'كلمة المرور', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _authenticate(register: false),
                  child: const Text('تسجيل الدخول'),
                ),
                OutlinedButton(
                  key: const Key('create-account'),
                  onPressed: _busy ? null : () => _authenticate(register: true),
                  child: const Text('إنشاء حساب جديد'),
                ),
                TextButton(
                  key: const Key('forgot-password'),
                  onPressed: _busy ? null : _recoverPassword,
                  child: const Text('نسيت كلمة المرور؟'),
                ),
                TextButton(
                  key: const Key('resend-confirmation'),
                  onPressed: _busy ? null : _resendConfirmation,
                  child: Text(_pendingConfirmation
                      ? 'لم تصلك الرسالة؟ إعادة إرسال التأكيد'
                      : 'عندي حساب ولم يصلني تأكيد البريد'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('google-sign-in'),
                  onPressed: _busy ? null : _googleSignIn,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('المتابعة باستخدام Google'),
                ),
                const Text(
                  'تسجيل Google يحتاج تفعيل مقدم الخدمة في Supabase. '
                  'تسجيل الإيميل يحتاج تفعيل رسالة التأكيد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 15),
                if (widget.allowGuest) TextButton.icon(
                  key: const Key('continue-as-guest'),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('الرجوع لحساباتي بدون تسجيل'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _PasswordRecoveryPage extends StatefulWidget {
  const _PasswordRecoveryPage();

  @override
  State<_PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<_PasswordRecoveryPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_busy) return;
    if (_password.text.length < 8 ||
        _password.text != _confirm.text) {
      setState(() => _message =
          'كلمة المرور لازم تكون 8 حروف على الأقل ومتطابقة في الخانتين.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تحديث كلمة المرور. تقدر تدخل بيها بعد كده.'),
      ));
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _message = AuthFeedback.serverError(e.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'تعذر تغيير كلمة المرور. اطلب رابط استعادة جديد.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعادة تعيين كلمة المرور')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل كلمة مرور جديدة للحساب الذي أرسلت له '
              'رسالة الاستعادة.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('recovery-password'),
            controller: _password, obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('recovery-confirm'),
            controller: _confirm, obscureText: true,
            decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
          ),
          const SizedBox(height: 12),
          if (_message.isNotEmpty) Text(_message),
          FilledButton(
            key: const Key('recovery-save'),
            onPressed: _busy ? null : _updatePassword,
            child: const Text('حفظ كلمة المرور'),
          ),
          if (_busy) const LinearProgressIndicator(),
        ]),
      ),
    )),
  );
}
