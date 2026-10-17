import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _backendUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _accent = Color(0xFFFFE324);
const _background = Color(0xFF101216);
const _surface = Color(0xFF1B1F26);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const configured = _backendUrl != '' && _publishableKey != '';
  if (configured) {
    await Supabase.initialize(
      url: _backendUrl,
      anonKey: _publishableKey,
    );
  }
  runApp(const HesabatyApp(backendConfigured: configured));
}

class HesabatyApp extends StatelessWidget {
  const HesabatyApp({super.key, this.backendConfigured = false});

  final bool backendConfigured;

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent,
          surface: _surface,
        ),
        cardTheme: const CardThemeData(
          color: _surface,
          margin: EdgeInsets.only(bottom: 12),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: _background),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: _surface,
          indicatorColor: Color(0xFF5A5317),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: backendConfigured ? const _AuthGate() : const _PreviewHome(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Supabase.instance.client.auth.currentUser == null
        ? const _SignInPage()
        : const _PreviewHome();
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authenticate({required bool register}) async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 6) {
      setState(() => _status = 'اكتب بريد إلكتروني صحيح وكلمة مرور 6 حروف على الأقل.');
      return;
    }
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (register) {
        final result = await auth.signUp(
          email: email,
          password: _password.text,
        );
        if (!mounted) return;
        setState(() => _status = result.session == null
            ? 'راجع إيميلك لتأكيد الحساب، وبعدها سجل دخول.'
            : 'تم إنشاء الحساب.');
      } else {
        await auth.signInWithPassword(email: email, password: _password.text);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'تعذر إتمام العملية. تحقق من الإنترنت وحاول مرة أخرى.');
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
                const SizedBox(height: 30),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
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
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_status, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  int _selected = 0;
  static const _titles = ['الرئيسية', 'المعاملات', 'الأقساط', 'التحليلات', 'الإعدادات'];
  static const _icons = [
    Icons.home_outlined,
    Icons.receipt_long_outlined,
    Icons.calendar_month_outlined,
    Icons.bar_chart_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حساباتي'),
        actions: [
          if (_backendUrl.isNotEmpty && _publishableKey.isNotEmpty &&
              Supabase.instance.client.auth.currentUser != null)
            IconButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(_titles[_selected], style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            if (_selected == 0) ...[
              const _Metric(title: 'الإجمالي', value: '—'),
              const _Metric(title: 'المصروفات', value: '—'),
              const _Metric(title: 'الإيداعات', value: '—'),
              const _Metric(title: 'المتبقي', value: '—'),
            ],
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.construction_outlined, color: _accent, size: 38),
                    SizedBox(height: 12),
                    Text('النسخة الأساسية من حساباتي 2.0',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'الشاشات دي للتأكد من تشغيل Flutter على أندرويد وآيفون. '
                      'لسه بننقل وظائف المصروفات والأقساط الحالية خطوة بخطوة. '
                      'مفيش بيانات حقيقية هتتمسح أو تتغيّر.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (value) => setState(() => _selected = value),
        destinations: List.generate(_titles.length,
          (index) => NavigationDestination(
            icon: Icon(_icons[index]),
            label: _titles[index],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}
