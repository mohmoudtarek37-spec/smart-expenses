/// User-facing diagnostic messages for email/password authentication.
/// Never include passwords, tokens, or account email addresses in diagnostics.
class AuthFeedback {
  static bool validEmail(String input) {
    final email = input.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) &&
        email.length <= 254;
  }

  static String serverError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('email_address_not_authorized') ||
        normalized.contains('email address not authorized')) {
      return 'Supabase منع إرسال رسالة التأكيد للعنوان ده. '
          'إرسال البريد الافتراضي محدود، ولازم نضبط SMTP خاص بالتطبيق.';
    }
    if (normalized.contains('email rate limit') ||
        normalized.contains('over_email_send_rate_limit') ||
        normalized.contains('email_send_rate_limit')) {
      return 'تم تجاوز حد رسائل التأكيد من السيرفر. استنى شوية '
          'قبل محاولة التسجيل تاني، أو جرّب بريدًا آخر بعدين.';
    }
    if (normalized.contains('signup is disabled') ||
        normalized.contains('signups not allowed') ||
        normalized.contains('signup_disabled') ||
        normalized.contains('email_provider_disabled')) {
      return 'إنشاء الحسابات متوقف في إعدادات السيرفر حاليًا. '
          'لازم نفعّله في Supabase.';
    }
    if (normalized.contains('already registered') ||
        normalized.contains('already been registered') ||
        normalized.contains('user_already_exists')) {
      return 'البريد ده مسجل قبل كده. جرّب تسجيل الدخول بدل إنشاء حساب.';
    }
    if (normalized.contains('weak password') ||
        normalized.contains('password should') ||
        normalized.contains('password is too short') ||
        normalized.contains('weak_password')) {
      return 'كلمة المرور مش مطابقة لشروط الأمان. '
          'جرّب 8 حروف أو أكتر مع أرقام وحروف.';
    }
    if (normalized.contains('invalid email') ||
        normalized.contains('email_address_invalid')) {
      return 'عنوان الإيميل غير صحيح. راجع كتابته وحاول تاني.';
    }
    if (normalized.contains('sending confirmation email') ||
        normalized.contains('error sending email') ||
        normalized.contains('smtp')) {
      return 'السيرفر مش قادر يرسل رسالة تأكيد الإيميل. '
          'لازم نراجع إعدادات إرسال البريد في Supabase.';
    }
    if (normalized.contains('email_not_confirmed')) {
      return 'الحساب محتاج تأكيد البريد الأول. افتح رسالة التفعيل '
          'أو اطلب إعادة إرسالها.';
    }
    if (normalized.contains('invalid login credentials')) {
      return 'الإيميل أو كلمة المرور غير صحيحة، أو لسه محتاج تأكيد البريد.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'الحساب موجود، لكن محتاج تأكيد الإيميل. '
          'افتح الرسالة في بريدك، وشوف مجلد Spam كمان.';
    }
    if (normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('connection') ||
        normalized.contains('clientexception')) {
      return 'التطبيق مش قادر يتصل بالسيرفر. '
          'راجع اتصال الإنترنت وجرب Wi-Fi أو بيانات الموبايل.';
    }
    // The actual backend message is shown for unknown errors so failures
    // can be diagnosed rather than silently pretending signup succeeded.
    return 'السيرفر رفض العملية: $message';
  }
}
