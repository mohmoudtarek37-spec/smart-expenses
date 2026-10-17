# حساباتي 2.0 — Flutter for Android and iOS

**هدف المشروع:** تجهيز تطبيق مالي يعمل على Android وiOS بكود Flutter مشترك، مع إطلاق Android على Google Play أولاً، ثم إطلاق iOS لاحقًا بعد استكمال متطلبات Apple.

## حالة التنفيذ

- ✅ بدأ مشروع Flutter مستقل على فرع `flutter-v2`.
- ✅ واجهة Flutter أولية بالعربي مبنية على شكل نسخة HTML (الرئيسية والتنقل والمعاملات والأقساط والتحليلات).
- ✅ معاملات محلية: إضافة وتعديل وحذف وحساب الإجماليات، مع حفظ مشفّر معزول لكل حساب لأغراض المعاينة فقط.
- ✅ أقساط محلية: إنشاء وتعديل وحذف، موعد الاستحقاق، تسجيل/إلغاء الدفع، ربط سحب موجود لمنع الحساب المزدوج، وحفظ المعاملة والدفع معًا.
- ✅ اختبارات معاملات/أقساط وتوافق مع نسخة مخزن البيانات الأولي، بدون ترحيل بيانات المستخدم القديمة.
- ✅ نقطة ربط Supabase Auth عبر `--dart-define` (بيانات الإعداد العامة فقط).
- 🚧 مطابقة كل تفاصيل HTML، دعم الميزات الباقية، وتخزين مناسب للإنتاج ومزامنة سحابية.
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

## تنبيه مهم بخصوص الأقساط

منطق الأقساط في نسخة Flutter الأولية **محلي وتجريبي**: لا يحدث سحب تلقائي ولا تذكير مضمون وقت إغلاق التطبيق. عند تسجيل القسط مدفوعًا، إما يُنشئ سحب واحد وإما يربط سحبًا موجودًا. حذف القسط يحتفظ بمعاملات السحب القديمة. لا تعتمد على النسخة الحالية في إدارة أموالك الفعلية: لا مزامنة، ولا استرجاع سحابي، ولا اعتماد نهائي لجودة الأجهزة أو أمان الإنتاج.


## Android signup and connectivity

- After `flutter create --platforms=android,ios --org io.github.mohmoudtarek37spec .`, run `dart tool/ensure_android_internet.dart` before **release** and preview builds. CI does this automatically.
- The owner chose **direct email/password signup without a confirmation email** as the temporary rollout policy. In Supabase > Authentication > Sign In / Providers > Email, disable **Confirm Email**, leaving Email enabled and new signups allowed. This provider setting has to be saved by the project owner in the Supabase dashboard; the app cannot override it.
- With Confirm Email disabled Supabase returns a session immediately. Flutter has been updated to explain that a null session means the server is **still** requiring verification, rather than asking users to wait for an email.
- We do not need Resend or a purchased domain for **direct signup**. The public Gmail `matarekstudio@gmail.com` is a **support contact address**, not an authorized sender identity on Resend.
- Without working outgoing SMTP, **forgot password** and email-change/recovery notifications will not reliably work. Preserve an alternate recovery strategy before launch.
- Direct signup using an unverified address has identity risks (someone can register someone else's address); never link or merge Google accounts solely by an unverified email match. Add abuse prevention/rate limiting and test on real Android devices before public launch.
- Google OAuth requires Google Cloud and Supabase provider configuration; it is not automatically enabled by switching off Confirm Email.

## استيراد رسائل SMS (Flutter preview)
- زر "استيراد SMS" يفتح **ملفًا يختاره المستخدم يدويًا**: TXT (رسائل مفصولة بسطر ---)، CSV (أعمدة sender/date/body)، أو JSON (قائمة رسائل).
- الحد 3 MB و200 رسالة لكل محاولة. لا نطلب READ_SMS ولا نقرأ صندوق الرسائل مباشرة.
- تظهر شاشة مراجعة لكل رسالة؛ المكرر وكود OTP والرسائل غير المكتملة لا يسمح بحفظها. يختار المستخدم الرسائل الصحيحة واحدةً واحدة ثم يؤكد.
- حفظ المعاملات يكون محليًا ويضاف بدون حذف القديم. المزامنة السحابية ما زالت تجريبية/يدوية.
- التنبؤ بالمبلغ/النوع محافظ؛ على المستخدم مراجعة المعاملات وتصحيح بياناتها بعد الاستيراد.
