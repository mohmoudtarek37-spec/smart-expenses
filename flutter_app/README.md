# حساباتي 2.0 — Flutter for Android and iOS

**هدف المشروع:** تجهيز تطبيق مالي يعمل على Android وiOS بكود Flutter مشترك، مع إطلاق Android على Google Play أولاً، ثم إطلاق iOS لاحقًا بعد استكمال متطلبات Apple.

## حالة التنفيذ

- ✅ بدأ مشروع Flutter مستقل على فرع `flutter-v2`.
- ✅ واجهة بداية قابلة للبناء لاختبار الأجهزة من غير بيانات إنتاجية.
- ✅ نقطة ربط Supabase Auth عبر `--dart-define` (بيانات الإعداد العامة فقط).
- 🚧 إعادة بناء الشاشات الحالية ووظائف المعاملات والأقساط والتحليلات.
- 🚧 مراجعة أمان المزامنة والتعارضات ونقل البيانات القديمة.
- 🚧 Google OAuth عبر متصفح نظام التشغيل + deep links لكل منصة.
- 🚧 Apple Sign In إذا لزم على iOS وفق سياسات App Store.
- 🚧 Google Play Billing والتحقق السيرفري من المشتريات.
- 🚧 التوقيع والاختبارات والأذونات وسياسة الخصوصية وملف AAB للإطلاق.

## البناء

من مجلد `flutter_app/` باستخدام Flutter stable:

```sh
flutter create --platforms=android,ios --org io.github.mohmoudtarek37spec .
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

**ملاحظة:** ملفات Android وiOS الأصلية سيتعين تثبيتها في المستودع قبل الإنتاج، بعد تحديد package ID / bundle ID النهائيين وتكوين التوقيع والروابط العميقة. البناء التجريبي الحالي على GitHub يولّد ملفات المنصتين، لكنه لا يثبت جاهزية نسخة iOS للنشر. بناء وتوقيع iOS يتطلبان macOS وXcode مؤهلين.

عند إعداد Supabase، استخدم المفاتيح العامة فقط مع:
`--dart-define=SUPABASE_URL=https://<project>.supabase.co`
و`--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...`.
**ممنوع** وضع مفاتيح service role أو Google Play Service Account أو مفاتيح التوقيع في المشروع العام.

## حفظ بيانات النسخة القديمة

ممنوع إزالة نسخة WebIntoApp أو مسح تخزينها. بياناتها على الهاتف لا تظهر تلقائيًا في Flutter. يلزم استيراد أو ترحيل بموافقة المستخدم، مع نسخ احتياطية واختبارات تمنع ضياع المصروفات. النسخة المعروضة حاليًا لا تعد بديلًا لبرنامج المستخدم اليومي.
