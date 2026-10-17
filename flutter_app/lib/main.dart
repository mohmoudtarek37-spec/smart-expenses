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
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
              )
            : FinanceShell(
                store: widget.guestStore,
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
              ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final StreamSubscription<AuthState> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return user == null
        ? const _SignInPage()
        : FinanceShell(
            key: ValueKey('user_${user.id}'),
            store: EncryptedTransactionStore(accountScope: user.id),
            cloudEnabled: true,
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
            onSignOut: () {
              Supabase.instance.client.auth.signOut();
            },
          );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _status = '';
  bool _statusIsError = false;

  @override
  void dispose() {
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
          _status = result.session == null
              ? 'طلب إنشاء الحساب اتقبل. افتح إيميلك واضغط على رابط '
                  'التأكيد، وشوف Spam لو مش لاقي الرسالة، '
                  'وبعدها ارجع وسجل دخول.'
              : 'تم إنشاء الحساب وتسجيل الدخول بنجاح.';
        });
      } else {
        await auth.signInWithPassword(
          email: email, password: password,
        ).timeout(const Duration(seconds: 25));
        if (mounted) {
          setState(() {
            _statusIsError = false;
            _status = 'تم تسجيل الدخول بنجاح.';
          });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const Text('سجّل دخولك علشان تحافظ على حسابك.',
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
                const SizedBox(height: 8),
                const Text(
                  'تسجيل الدخول باستخدام Google على أندرويد وآيفون '
                  'سيُفعّل بعد إعداد روابط الرجوع الآمنة لكل نظام.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

