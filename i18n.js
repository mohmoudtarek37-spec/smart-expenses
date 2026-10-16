/* Arabic/English presentation only. Stored transaction values and categories remain unchanged. */
(function(){
  'use strict';
  const key='hesabaty_ui_language';
  const dict={
  "حساباتي": "My Accounts",
  "فلوسك في مكان واحد": "Your money in one place",
  "الرئيسية": "Home",
  "المعاملات": "Transactions",
  "الأقساط": "Installments",
  "التحليلات": "Analytics",
  "الإعدادات": "Settings",
  "إضافة معاملة جديدة": "Add transaction",
  "تغيير المظهر": "Change appearance",
  "تفعيل الوضع الفاتح": "Switch to light mode",
  "تفعيل الوضع الداكن": "Switch to dark mode",
  "الصفحات الرئيسية": "Main navigation",
  "جاري فتح حساباتك...": "Loading your accounts...",
  "نظرة عامة": "Overview",
  "كل حسابات الشهر واضحة قدامك": "Your monthly finances at a glance",
  "الإجمالي": "Total",
  "إجمالي إيداعات الشهر": "Total deposits this month",
  "إيداعات هذا الشهر فقط": "Deposits this month only",
  "المتبقي": "Remaining",
  "السحب": "Withdrawals",
  "الإيداع": "Deposits",
  "جنيه": "EGP",
  "ج.م": "EGP",
  "الإجمالي − السحب": "Total minus withdrawals",
  "خرجت خلال الشهر": "Spent this month",
  "تفاصيل المبالغ الواردة": "Incoming transactions",
  "نسبة المصروفات": "Spending ratio",
  "نسبة السحب من إجمالي إيداعات الشهر": "Withdrawals as a share of monthly deposits",
  "أضف أول إيداع لعرض نسبة المصروفات": "Add your first deposit to see spending ratio",
  "مصروفاتك تجاوزت الإيداعات": "Spending exceeded deposits",
  "المصروفات حسب التصنيف": "Spending by category",
  "التفاصيل": "Details",
  "آخر المعاملات": "Recent transactions",
  "عرض الكل": "View all",
  "لحد دلوقتي مفيش مصروفات في الشهر ده": "No spending this month yet",
  "أضف أول معاملة أو استورد رسالة SMS": "Add a transaction or import an SMS",
  "استيراد رسائل SMS": "Import SMS messages",
  "استيراد SMS": "Import SMS",
  "رسائل SMS": "SMS messages",
  "الشهر السابق": "Previous month",
  "الشهر التالي": "Next month",
  "تفاصيل كل سحب وإيداع، ومعاه إثبات العملية": "All withdrawals and deposits with their receipts",
  "معاملة يدوية": "Manual transaction",
  "الكل": "All",
  "بحث بالاسم أو المصدر أو النص...": "Search name, source or message...",
  "بحث المعاملات": "Search transactions",
  "لا توجد معاملات مطابقة في هذا الشهر": "No matching transactions this month",
  "لا توجد معاملات مطابقة": "No matching transactions",
  "مشتريات": "Shopping",
  "مصاريف شحن": "Mobile top-ups",
  "اشتراكات": "Subscriptions",
  "كهرباء": "Electricity",
  "مياه": "Water",
  "مستلزمات بيت": "Household",
  "مصاريف شخصية": "Personal expenses",
  "مطاعم": "Restaurants",
  "صحة": "Healthcare",
  "مواصلات": "Transport",
  "فواتير": "Bills",
  "أخرى": "Other",
  "راتب": "Salary",
  "تحويل وارد": "Incoming transfer",
  "البنك الأهلي": "National Bank of Egypt",
  "بنك مصر": "Banque Misr",
  "نقدي": "Cash",
  "مصدر آخر": "Other source",
  "مدفوع": "Paid",
  "متأخر": "Overdue",
  "مستحق اليوم": "Due today",
  "منتظر الدفع": "Pending payment",
  "مواعيد دفع الأقساط الشهرية، وتسجل السحب وقت الدفع فقط": "Monthly installments; withdrawals are recorded only when you mark a payment",
  "أقساط الشهر": "This month's installments",
  "المتبقي دفعه": "Left to pay",
  "تنبيهات الأقساط قبل موعدها بيوم: التذكير داخل التطبيق بيظهر عند فتحه، ولتنبيه مضمون أثناء إغلاقه صدّر المواعيد إلى تقويم الآيفون وفعّل تنبيهات Calendar.": "Installment reminders appear when the app is opened. For alerts while it is closed, export due dates to your calendar.",
  "إضافة قسط جديد": "Add installment",
  "إضافة قسط": "Add installment",
  "تصدير للتقويم": "Export to calendar",
  "الأقساط المسجلة": "Registered installments",
  "قسط": "Installment",
  "يوم": "Day",
  "من كل شهر": "of every month",
  "مستمر": "Ongoing",
  "الاستحقاق:": "Due:",
  "غير مسدد": "Unpaid",
  "تسجيل الدفع": "Record payment",
  "تم تسجيل الدفع": "Payment recorded",
  "مفيش أقساط مسجلة للشهر ده، ابدأ بإضافة أول قسط": "No installments scheduled this month",
  "تعديل": "Edit",
  "الاستحقاق": "Due date",
  "اعرف فلوسك راحت فين وقارن بين الشهور": "See where your money went and compare months",
  "حركة آخر 6 شهور": "Last 6 months",
  "المقارنة الشهرية": "Monthly comparison",
  "سحب الشهر الحالي": "This month's withdrawals",
  "سحب الشهر السابق": "Last month's withdrawals",
  "توزيع المصروفات": "Spending breakdown",
  "مفيش مصروفات للتحليل في الشهر ده": "No spending to analyze this month",
  "مؤشرات الشهر": "Monthly indicators",
  "نسبة المصروفات من الإيداعات": "Spending as % of deposits",
  "متبقي الشهر": "Monthly balance",
  "عدد العمليات المسجلة": "Recorded transactions",
  "الشهر السابق لم يكن فيه مصروفات مسجلة، لذلك المقارنة المئوية غير متاحة.": "No expenses last month, so a percentage comparison is not available.",
  "مفيش مصروفات مسجلة في الشهرين.": "No expenses recorded in either month.",
  "مصروفات الشهر": "This month's spending",
  "أعلى": "higher",
  "أقل": "lower",
  "من الشهر السابق بـ": "than last month by",
  "مقارنة مبدئية لأن الشهر لسه ما خلصش": "Provisional, since the month is not over",
  "البيانات محفوظة على جهازك، من غير حساب أو سيرفر": "Data stays on your device; no account or server",
  "الإصدار الحالي": "Current version",
  "قاعدة البيانات": "Database",
  "جاهز": "Ready",
  "مكان حفظ البيانات": "Storage location",
  "على الجهاز": "on this device",
  "احتياطي على الجهاز": "fallback on this device",
  "عدد المعاملات": "Transaction count",
  "الإجمالي في كل الشهور": "Across all months",
  "حماية بياناتك": "Protect your data",
  "احفظ نسخة احتياطية بعد كل فترة وقبل كل تحديث. حذف التطبيق أو بيانات Safari قد يمسح النسخة المحلية.": "Export a backup regularly and before updates. Removing the app or clearing browser data could erase local data.",
  "تصدير نسخة احتياطية": "Export backup",
  "استعادة نسخة": "Restore backup",
  "لا يسمح لموقع ويب بقراءة تطبيق Messages مباشرة. يمكنك استيراد نص رسالة، أو ملف TXT / JSON / CSV ناتج من اختصار Apple Shortcuts. الربط التلقائي الكامل لم يُنفّذ في هذه النسخة.": "Web apps cannot read your SMS inbox directly. Paste a message or import a TXT / JSON / CSV file.",
  "استيراد رسالة": "Import message",
  "تعليمات صيغة الاستيراد": "Import format guide",
  "تنبيهات الأقساط": "Installment reminders",
  "تنبيهات داخل التطبيق عند فتحه، مع تصدير مواعيد التقويم وتذكير قبلها بيوم. لا توجد إشعارات خلفية تلقائية من التطبيق دون إعداد إضافي.": "Alerts show when you open the app. You can export dates to your calendar, but background notifications require additional setup.",
  "تصدير ملف التقويم": "Export calendar file",
  "اختبار التصميم": "Preview design",
  "لو لسه معندكش بيانات، تقدر تضيف بيانات تجريبية للتأكد من كل الحسابات.": "If you have no data yet, add demo transactions to test the calculations.",
  "إضافة بيانات تجريبية": "Add demo data",
  "مسح كل البيانات": "Delete all data",
  "مشروع شخصي بدون اتصالات خارجية أو تتبع للمعلومات المالية.": "Personal project; financial data is not tracked or sent to a server.",
  "تعديل المعاملة": "Edit transaction",
  "المبلغ بالجنيه": "Amount (EGP)",
  "التاريخ": "Date",
  "الوصف": "Description",
  "مثلاً: مشتريات السوبر ماركت": "e.g. Groceries",
  "التصنيف": "Category",
  "مصدر العملية": "Transaction source",
  "نص رسالة SMS (اختياري)": "SMS message (optional)",
  "الصق الرسالة الأصلية للاحتفاظ بيها داخل المعاملة": "Paste the original SMS for your records",
  "إرفاق صورة أصلية أو إيصال (اختياري)": "Attach original image or receipt (optional)",
  "يفضل صورة بدون بيانات بطاقتك الكاملة. الصورة هتتحفظ محليًا.": "Avoid images showing full card numbers. Images remain on your device.",
  "تحويل بين حساباتي / تجاهل من إجمالي السحب والإيداع": "Transfer between my accounts / Exclude from totals",
  "حفظ التعديل": "Save changes",
  "حفظ المعاملة": "Save transaction",
  "حذف المعاملة": "Delete transaction",
  "اكتب مبلغ وتاريخ صحيحين": "Enter a valid amount and date",
  "تم تعديل المعاملة": "Transaction updated",
  "تمت إضافة المعاملة": "Transaction added",
  "تحذف المعاملة نهائيًا؟": "Delete this transaction permanently?",
  "تم حذف المعاملة": "Transaction deleted",
  "إغلاق": "Close",
  "المصدر": "Source",
  "هذه العملية مستبعدة من الحسابات (تحويل بين حساباتك).": "This transfer is excluded from totals.",
  "نص الرسالة المحفوظ": "Saved message",
  "حفظ إيصال بصورة PNG": "Save receipt as PNG",
  "الصورة الأصلية المرفقة": "Original attached image",
  "صورة مرفقة للمعاملة": "Attached transaction image",
  "إثبات المعاملة": "Transaction proof",
  "إيصال مولّد من نص الرسالة": "Receipt generated from message",
  "ليس لقطة شاشة أصلية من Messages": "Not an original Messages screenshot",
  "الصق نص الرسالة المالية هنا أو استورد ملف من Apple Shortcuts. مش بنقرأ صندوق رسائل الآيفون مباشرة.": "Paste a financial SMS or import a Shortcuts export; the SMS inbox is not read directly.",
  "مرسل الرسالة": "Message sender",
  "مثلاً CIB": "e.g. CIB",
  "نص رسالة SMS": "SMS message",
  "تحليل الرسالة": "Analyze message",
  "استيراد ملف TXT / CSV / JSON": "Import TXT / CSV / JSON",
  "الصق نص الرسالة الأول": "Paste the message first",
  "مراجعة قبل التسجيل": "Review before saving",
  "راجع نوع العملية والمبلغ قبل الحفظ. الرسائل المكررة هتتجاهل تلقائيًا.": "Review transaction type and amount. Duplicate messages are skipped automatically.",
  "رسالة": "Message",
  "مكررة": "Duplicate",
  "مراجعة ضرورية": "Needs review",
  "تم التحليل": "Analyzed",
  "النوع": "Type",
  "غير محدد": "Unspecified",
  "تجاهل": "Skip",
  "المبلغ": "Amount",
  "تحويل بين حساباتي (استبعاد)": "Transfer between own accounts (exclude)",
  "حفظ الرسائل المؤكدة": "Save confirmed messages",
  "لو التحليل مش متأكد من نوع أو مبلغ عملية، اخترهم يدويًا أو تجاهل الرسالة.": "If analysis is uncertain, confirm the type and amount manually or skip the message.",
  "عملية سحب": "Withdrawal",
  "تعديل القسط": "Edit installment",
  "اسم القسط": "Installment name",
  "مثلاً: قسط الموبايل": "e.g. Phone installment",
  "القيمة الشهرية": "Monthly amount",
  "يوم الدفع": "Payment day",
  "بداية القسط": "Starting month",
  "عدد الأشهر": "Number of months",
  "مستمر)": "ongoing)",
  "لو اخترت يوم 31 في شهر أقصر، هيكون الاستحقاق آخر يوم في الشهر. القسط مش هيتخصم تلقائيًا غير بعد تسجيل الدفع.": "If you choose day 31, shorter months use their last day. Payment is deducted only when recorded.",
  "حفظ تعديل القسط": "Save installment changes",
  "حذف القسط": "Delete installment",
  "راجع بيانات القسط": "Review installment details",
  "تم حفظ القسط": "Installment saved",
  "تم حذف القسط مع الاحتفاظ بالمعاملات": "Installment removed; transactions retained",
  "القسط مدفوع بالفعل في الشهر ده": "Installment already paid this month",
  "تسجيل دفع القسط": "Record installment payment",
  "طريقة التسجيل": "Recording method",
  "إنشاء عملية سحب جديدة بالقيمة نفسها": "Create a new withdrawal",
  "ربط بسحب موجود:": "Link an existing withdrawal:",
  "لو كانت رسالة البنك اتسجلت بالفعل، اختار العملية الموجودة بدل إنشاء سحب جديد عشان المبلغ ما يتحسبش مرتين.": "If the bank SMS was imported, link that transaction to avoid counting the amount twice.",
  "تأكيد دفع القسط": "Confirm installment payment",
  "لا توجد معاملات": "No transactions",
  "إضافة": "Add",
  "حفظ": "Save",
  "تأكيد": "Confirm",
  "إلغاء": "Cancel",
  "إيداع": "Deposit",
  "سحب": "Withdrawal",
  "مستبعدة": "Excluded",
  "يدوي": "Manual",
  "التخزين المحلي الاحتياطي نشط؛ تأكد من تصدير نسخة احتياطية دوريًا.": "Fallback local storage is active. Export backups regularly.",
  "قسط/أقساط تستحق قريبًا أو متأخرة. افتح صفحة الأقساط للتفاصيل.": "installments are due soon or overdue. Check the Installments page.",
  "صورة": "Image",
  "التالي": "Next",
  "السابق": "Previous",
  "الآن": "Now",
  "صيغة بيانات غير معروفة": "Unrecognized data format",
  "تفاصيل المعاملة": "Transaction details",
  "نوع العملية يحتاج مراجعة": "Transaction type needs review",
  "الملف فارغ": "File is empty",
  "صيغة JSON غير صحيحة": "Invalid JSON format",
  "تحتاج مراجعة": "Needs review",
  "المعاملة غير موجودة": "Transaction not found",
  "موعد للتقويم. افتح الملف وأضف المواعيد إلى Calendar.": "calendar events. Open the file and add the dates to your calendar.",
  "تم تجهيز نسخة احتياطية؛ احتفظ بيها في Files أو iCloud Drive": "Backup created. Save it to Files or iCloud Drive.",
  "ملف النسخة الاحتياطية أكبر من المسموح": "Backup file is too large",
  "النسخة من إصدار أحدث؛ حدث التطبيق أولًا": "Backup comes from a newer version; update the app first",
  "هتستبدل البيانات الحالية": "This will replace the current data",
  "عملية) بالنسخة دي": "transactions) with the backup",
  "عملية). خُد نسخة احتياطية من بياناتك الحالية الأول. هل تؤكد؟": "transactions). Back up your existing data first. Continue?",
  "تعذر قراءة النسخة الاحتياطية": "Could not read backup",
  "صيغة استيراد رسائل Shortcuts": "Shortcuts message import format",
  "مثال ملف JSON:": "Example JSON file:",
  "أو ملف CSV:": "Or CSV file:",
  "اتمسحت كل البيانات من التطبيق": "All app data has been deleted",
  "حجم ملف الرسائل كبير جدًا (الحد 3 ميجابايت)": "Message file exceeds the 3 MB limit",
  "لا توجد رسائل داخل الملف": "No messages in file",
  "تعذر قراءة ملف الرسائل": "Could not read message file",
  "حصل خطأ أثناء فتح التطبيق. جرّب تحديث الصفحة، واحتفظ بنسخة من بيانات المتصفح قبل أي مسح.": "The app couldn't load. Try refreshing, and keep a backup before clearing browser data.",
  "مثال: Your card has been debited with EGP 850.00 at Carrefour...": "Example: Your card has been debited with EGP 850.00 at Carrefour...",
  "تخصيص التطبيق": "Personalization",
  "الاسم المعروض": "Display name",
  "غيّر اسم الترحيب اللي فوق": "Update the name in the welcome message",
  "تغيير الاسم": "Change name",
  "لون التمييز": "Accent color",
  "اختر اللون المفضل للأيقونات والأزرار": "Choose a color for icons and buttons",
  "أصفر": "Yellow",
  "أخضر فاتح": "Mint green",
  "برتقالي": "Orange",
  "أزرق": "Blue",
  "أخضر": "Green",
  "شفافية الزجاج": "Glass appearance",
  "Clear زجاج شفاف • Blur زجاج ضبابي": "Clear transparent glass • Blur frosted glass",
  "اكتب اسمك": "Enter your name",
  "أهلاً يا": "Hello,",
  "أهلًا بيك": "Welcome",
  "أهلًا بيك في حساباتي": "Welcome to My Accounts",
  "تحب نناديك بإيه؟ اسمك هيتحفظ على جهازك بس.": "What should we call you? Your name stays on this device.",
  "اسمك": "Your name",
  "ابدأ": "Continue"
};
  const entries=Object.entries(dict).sort((a,b)=>b[0].length-a[0].length);
  const textOriginal=new WeakMap(),textApplied=new WeakMap();
  const translateCache=new Map();
  const attrOriginal=new WeakMap(),attrApplied=new WeakMap();
  const skipSelector='script,style,noscript,textarea,code,pre,.txn-name,.txn-meta,.install-title,.receipt,.preview-raw,.sms-preview,.sms-result,.sms-results,.money,.large-amount,.chart-label,.txn-amt';
  let lang='ar';
  try{lang=localStorage.getItem(key)==='en'?'en':'ar'}catch(e){}
  function english(s){
    if(!s || !/[\u0600-\u06ff]/.test(s))return s;
    if(translateCache.has(s))return translateCache.get(s);
    const exact=dict[s.trim()];
    if(exact){const v=s.replace(s.trim(),exact);translateCache.set(s,v);return v;}
    let result=s;
    for(const [ar,en] of entries){
      if(result.includes(ar))result=result.split(ar).join(en);
    }
    if(translateCache.size>600)translateCache.clear();
    translateCache.set(s,result);
    return result;
  }
  function patchNode(node){
    const holder=node.parentElement;
    if(!holder || holder.closest(skipSelector))return;
    const val=node.nodeValue;
    const previous=textApplied.get(node);
    if(!textOriginal.has(node)||val!==previous)textOriginal.set(node,val);
    const source=textOriginal.get(node);
    const target=lang==='en'?english(source):source;
    if(val!==target)node.nodeValue=target;
    textApplied.set(node,target);
  }
  function patchAttrs(el){
    if(el.matches('input[type="text"][name="note"],textarea[name="sms"]'))return;
    let originals=attrOriginal.get(el)||{},applied=attrApplied.get(el)||{};
    for(const att of ['placeholder','title','aria-label']){
      if(!el.hasAttribute(att))continue;
      const value=el.getAttribute(att);
      if(!(att in originals)||value!==applied[att]) originals[att]=value;
      const target=lang==='en'?english(originals[att]):originals[att];
      if(value!==target)el.setAttribute(att,target);
      applied[att]=target;
    }
    attrOriginal.set(el,originals);attrApplied.set(el,applied);
  }
  function translateTree(root){
    if(!root)return;
    if(root.nodeType===3){patchNode(root);return;}
    if(root.nodeType!==1)return;
    if(root.id==='langToggle')return;
    if(root.matches(skipSelector))return;
    patchAttrs(root);
    for(let c=root.firstChild;c;c=c.nextSibling)translateTree(c);
  }
  function renderLanguageButton(){
    const btn=document.getElementById('langToggle');
    if(btn){
      btn.textContent=lang==='ar'?'EN':'ع';
      btn.setAttribute('aria-label',lang==='ar'?'Switch to English':'التبديل إلى العربية');
      btn.title=lang==='ar'?'English':'العربية';
    }
    document.title=lang==='ar'?'حساباتي | Smart Expenses':'My Accounts | Smart Expenses';
  }
  function translatePage(){
    document.documentElement.lang=lang;
    document.documentElement.dir=lang==='en'?'ltr':'rtl';
    for(const id of ['app','modalRoot','toast','bannerArea'])translateTree(document.getElementById(id));
    renderLanguageButton();
  }
  function setLanguage(next){
    lang=next==='en'?'en':'ar';
    try{localStorage.setItem(key,lang)}catch(e){}
    if(typeof window.render==='function')window.render();
    translatePage();
  }
  document.addEventListener('click',e=>{
    if(e.target.closest('#langToggle'))setLanguage(lang==='ar'?'en':'ar');
  });
  const obs=new MutationObserver(mutations=>{
    for(const m of mutations){
      if(m.type==='characterData')patchNode(m.target);
      if(m.type==='attributes' && m.target.id!=='langToggle')patchAttrs(m.target);
      if(m.type==='childList')for(const n of m.addedNodes)translateTree(n);
    }
  });
  const start=()=>{
    translatePage();
    obs.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['title','placeholder','aria-label']});
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
  else start();
  window.hesabatyI18n={setLanguage,getLanguage:()=>lang,translate:english};
})();
