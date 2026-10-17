import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Reads only public Auth health/settings; does not create users or log emails,
/// passwords, JWTs, API keys, financial data or any other personal information.
class AuthServerDiagnostics {
  const AuthServerDiagnostics({
    required this.reachable, this.signupAllowed, this.emailEnabled,
    this.googleEnabled,
  });

  final bool reachable;
  final bool? signupAllowed;
  final bool? emailEnabled;
  final bool? googleEnabled;

  static AuthServerDiagnostics fromPublicSettings(
      Map<String, dynamic> settings) {
    final providers = settings['external'];
    final external = providers is Map ? providers : const {};
    return AuthServerDiagnostics(
      reachable: true,
      signupAllowed: settings['disable_signup'] is bool
          ? settings['disable_signup'] == false : null,
      emailEnabled: external['email'] is bool ? external['email'] : null,
      googleEnabled: external['google'] is bool ? external['google'] : null,
    );
  }

  String get humanMessage {
    if (!reachable) {
      return 'الموبايل مش قادر يتصل بسيرفر حساباتي. '
          'جرّب Wi-Fi أو بيانات الهاتف.';
    }
    if (signupAllowed == false) {
      return 'الاتصال شغال، لكن إعدادات Supabase مانعة إنشاء حسابات جديدة.';
    }
    if (emailEnabled == false) {
      return 'الاتصال شغال، لكن تسجيل الدخول بالإيميل متوقف في Supabase.';
    }
    final google = googleEnabled == false
        ? 'Google Login مش مفعّل على السيرفر.'
        : googleEnabled == true
            ? 'Google Login مفعّل على السيرفر.'
            : 'مش قادرين نحدد حالة Google Login.';
    return 'الاتصال بسيرفر حساباتي شغال. $google'
        ' فحص الاتصال لا يؤكد إن خدمة إرسال إيميلات التفعيل شغالة؛ '
        'لازم نجرب إنشاء حساب ووصول رسالة فعلية.';
  }

  static Future<AuthServerDiagnostics> check({
    required String backendUrl, required String publishableKey,
  }) async {
    if (backendUrl.isEmpty || publishableKey.isEmpty) {
      return const AuthServerDiagnostics(reachable: false);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final root = Uri.parse(backendUrl);
      if (root.scheme != 'https') {
        return const AuthServerDiagnostics(reachable: false);
      }
      Future<HttpClientResponse> fetch(String path) async {
        final request = await client.getUrl(root.resolve(path))
            .timeout(const Duration(seconds: 8));
        request.headers.set('apikey', publishableKey);
        return request.close().timeout(const Duration(seconds: 8));
      }
      final health = await fetch('/auth/v1/health');
      await health.drain<void>();
      if (health.statusCode != 200) {
        return const AuthServerDiagnostics(reachable: false);
      }
      try {
        final settings = await fetch('/auth/v1/settings');
        if (settings.statusCode != 200) {
          await settings.drain<void>();
          return const AuthServerDiagnostics(reachable: true);
        }
        final json = jsonDecode(await utf8.decoder
            .bind(settings).join().timeout(const Duration(seconds: 8)));
        if (json is Map<String, dynamic>) {
          return fromPublicSettings(json);
        }
      } catch (_) {
        // Network health succeeded even if settings cannot be retrieved.
      }
      return const AuthServerDiagnostics(reachable: true);
    } on SocketException {
      return const AuthServerDiagnostics(reachable: false);
    } on TimeoutException {
      return const AuthServerDiagnostics(reachable: false);
    } on HandshakeException {
      return const AuthServerDiagnostics(reachable: false);
    } finally {
      client.close(force: true);
    }
  }
}
