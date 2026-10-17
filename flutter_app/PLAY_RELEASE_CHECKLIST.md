# حساباتي 2.0: شروط إصدار Google Play

النسخة الحالية Preview لا تُعتبر إنتاجية إلا بعد الاختبارات والإعدادات.

## قبل رفع AAB
- اضبط هوية package: io.github.mohmoudtarek37spec.hesabaty.
- جهز مفتاح Android upload signing. احتفظ بالمفتاح وكلمات السر في مكان آمن؛
  لا تضعها في GitHub أو في أي محادثة.
- أنشئ GitHub Actions Secrets بالاسم:
  ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD /
  ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD.
- شغّل Workflow: Hesabaty Android Signed Release AAB.
- لا ترفع إصدار Debug APK كإصدار تجاري؛ استخدم ملف AAB الموقع.
- اختبر تسجيل الحساب + وصول التفعيل + الدخول بجوجل + استرجاع كلمة المرور
  والتخزين السحابي وRLS على جهازين مختلفين، وحالات تعارض البيانات.
- Google Play: انشئ منتج الاشتراك `hesabaty_premium_monthly`
  وفعّل Google Play Developer API وتفويض الخدمة في Play Console.
- في Supabase Edge Functions عرّف سر
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON لاستخدامه في تحقق الاشتراكات.
  API Function `verify-play-subscription` مش هتسمح بالشراء قبل الإعداد.
- تفعيل Resend SMTP للدومين المعتمد؛ لا تعطل تأكيد البريد.
- سياسة الخصوصية وData Safety ومراجعة أذونات SMS:
  التطبيق بيستورد ملف يدويًا ولا يطلب READ_SMS.
- لازم تختبر تطبيقك على Internal Testing في Play Console وتختبر الطلبات،
  ثم تراجع track وcountry وpricing وخطة Premium.
- مراجعة تصميم الواجهات بالعربي والإنجليزي، التواريخ والتقارير والأقساط.
- تحذير: قاعدة البيانات تحفظ snapshot حتى 8 MB، والإيصالات الأكبر لازم
  تترفع منفصلة لتجنب فشل المزامنة.

## طريقة متابعة
Android Preview: .github/workflows/flutter-v2.yml
Signed Release: .github/workflows/android-release.yml

النشر على متجر Google Play يحتاج إجراء من مالك حساب المطور والموافقة
على المعلومات القانونية والمدفوعات. CI لا ينشر تلقائيًا.
