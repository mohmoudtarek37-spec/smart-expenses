import { createClient } from '@supabase/supabase-js';

// Public client credentials only. No privileged Supabase or Google Play secrets.
const settings = window.HESABATY_SUPABASE || {};
const configured = /^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(settings.url || '')
  && /^(sb_publishable_|eyJ)/.test(settings.publishableKey || '');
const bridge = () => window.hesabatyBridge;
const safe = value => String(value ?? '').replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
}[char]));
const hasFinancialData = data =>
  !!((data?.transactions?.length || 0) + (data?.installments?.length || 0));

let client = null;
let currentUser = null;
let revision = null;
let busy = false;
let dirty = false;
let blocked = false;
let suppressPush = false;
let timer = null;
let message = '';
let premium = false;

function panel() {
  if (!configured) {
    return '<div class="card"><strong>☁️ حسابك والمزامنة</strong>' +
      '<p class="footnote">خدمة الحسابات السحابية في مرحلة الإعداد. بياناتك الحالية محفوظة على جهازك.</p></div>';
  }
  if (!currentUser) {
    return '<div class="card"><strong>☁️ حسابك والمزامنة</strong>' +
      '<p class="footnote">سجّل دخولك لاسترجاع حساباتك على أجهزتك. بياناتك القديمة لن تُحذف.</p>' +
      '<form id="hesabatyCloudForm" autocomplete="on">' +
      '<div class="field"><label for="hesabatyEmail">البريد الإلكتروني</label>' +
      '<input id="hesabatyEmail" name="email" type="email" autocomplete="email" required placeholder="email@example.com"></div>' +
      '<div class="field"><label for="hesabatyPassword">كلمة المرور</label>' +
      '<input id="hesabatyPassword" name="password" type="password" autocomplete="current-password" required minlength="6"></div>' +
      '<div class="buttons"><button class="btn" type="submit" value="signin">تسجيل الدخول</button>' +
      '<button class="btn secondary" type="submit" value="signup">إنشاء حساب</button></div></form>' +
      '<div class="buttons" style="margin-top:12px"><button class="btn secondary block" type="button" data-cloud="google">المتابعة بحساب Google</button></div>' +
      '<p class="footnote" aria-live="polite">' + safe(message) + '</p></div>';
  }
  const status = blocked ? 'تعارض بيانات: المزامنة متوقفة لحماية حساباتك.'
    : busy ? 'جاري المزامنة…' : dirty ? 'تغييرات محلية بانتظار المزامنة.' : 'المزامنة جاهزة.';
  return '<div class="card"><strong>☁️ حسابك والمزامنة</strong>' +
    '<p class="footnote">مسجل بحساب: ' + safe(currentUser.email || '') + '</p>' +
    '<p class="footnote" aria-live="polite">' + safe(message || status) + '</p>' +
    '<p class="footnote">الخطة: ' + (premium ? 'Premium' : 'مجانية') + '</p>' +
    '<div class="buttons"><button type="button" class="btn secondary small" data-cloud="sync">مزامنة الآن</button>' +
    '<button type="button" class="btn secondary small" data-cloud="import-guest">نقل بيانات النسخة القديمة</button>' +
    '<button type="button" class="btn secondary small" data-cloud="signout">تسجيل خروج</button></div>' +
    '<p class="footnote">اشتراكات Premium المدفوعة ستُفعّل بعد ربط Google Play Billing والتحقق منها على السيرفر.</p></div>';
}

function refresh() {
  if (bridge()?.renderSettingsIfVisible) bridge().renderSettingsIfVisible();
}

function setMessage(value) {
  message = value;
  refresh();
}

async function guardedReplace(data) {
  suppressPush = true;
  try {
    await bridge().replace(data);
  } finally {
    suppressPush = false;
  }
}

function mergeSnapshots(remote, local) {
  const combined = { ...remote, ...local };
  const mergeById = (base, additions) => {
    const records = new Map();
    for (const entry of base || []) if (entry?.id) records.set(entry.id, entry);
    for (const entry of additions || []) {
      if (!entry?.id) continue;
      if (Array.isArray(entry.payments) && records.has(entry.id)) {
        const previous = records.get(entry.id);
        const payments = new Map();
        for (const p of previous.payments || []) if (p?.month) payments.set(p.month, p);
        for (const p of entry.payments) if (p?.month) payments.set(p.month, p);
        records.set(entry.id, { ...previous, ...entry, payments: [...payments.values()] });
      } else {
        records.set(entry.id, entry);
      }
    }
    return [...records.values()];
  };
  combined.transactions = mergeById(remote?.transactions, local?.transactions);
  combined.installments = mergeById(remote?.installments, local?.installments);
  combined.customCategories = [...new Set([
    ...(remote?.customCategories || []), ...(local?.customCategories || [])
  ])];
  return combined;
}

async function getRemote() {
  const { data, error } = await client.from('user_snapshots')
    .select('snapshot,revision').eq('user_id', currentUser.id).maybeSingle();
  if (error) throw error;
  return data;
}

async function saveRemote(snapshot) {
  // Optimistic concurrency: never silently overwrite newer data from another device.
  if (revision === null) {
    const { data, error } = await client.from('user_snapshots')
      .insert({ user_id: currentUser.id, snapshot, revision: 1 })
      .select('revision').single();
    if (error) throw error;
    revision = data.revision;
    return;
  }
  const { data, error } = await client.from('user_snapshots')
    .update({
      snapshot, revision: revision + 1,
      updated_at: new Date().toISOString()
    })
    .eq('user_id', currentUser.id)
    .eq('revision', revision)
    .select('revision').maybeSingle();
  if (error) throw error;
  if (!data) {
    blocked = true;
    throw new Error('نسخة أحدث محفوظة من جهاز آخر. اضغط مزامنة الآن لدمج البيانات.');
  }
  revision = data.revision;
}

async function push() {
  if (!currentUser || !dirty || busy || blocked) return;
  busy = true;
  try {
    const originalUser = currentUser.id;
    const snapshot = bridge().read();
    await saveRemote(snapshot);
    if (currentUser?.id === originalUser) {
      dirty = JSON.stringify(bridge().read()) !== JSON.stringify(snapshot);
      setMessage(dirty ? 'فيه تعديلات جديدة، هنحفظها كمان.' : '✓ بياناتك محفوظة على حسابك.');
    }
  } catch (error) {
    dirty = true;
    setMessage('تعذر الحفظ السحابي: ' + String(error?.message || error));
  } finally {
    busy = false;
    if (dirty && !blocked && currentUser) queuePush();
  }
}

function queuePush() {
  if (!currentUser || suppressPush || blocked) return;
  dirty = true;
  clearTimeout(timer);
  timer = setTimeout(() => void push(), 1100);
  refresh();
}

async function readPremium() {
  if (!currentUser) { premium = false; return; }
  const { data, error } = await client.from('user_entitlements')
    .select('status,expires_at').eq('user_id', currentUser.id).maybeSingle();
  if (error) {
    premium = false;
    return;
  }
  premium = !!data && (data.status === 'active' || data.status === 'grace_period')
    && (!data.expires_at || Date.parse(data.expires_at) > Date.now());
}

async function importGuest(ask = true) {
  const guest = await bridge().readGuest();
  if (!hasFinancialData(guest)) {
    if (!ask) return false;
    setMessage('مفيش معاملات قديمة على نفس الجهاز لاستيرادها.');
    return false;
  }
  if (!confirm('لقينا بيانات قديمة محفوظة على الجهاز. هل تحب نضيفها لحسابك السحابي؟ مش هنمسح الأصل.')) {
    return false;
  }
  const merged = mergeSnapshots(bridge().read(), guest);
  await guardedReplace(merged);
  dirty = true;
  return true;
}

async function connectSession(session) {
  await bridge().ready;
  const nextUser = session?.user || null;
  if (nextUser?.id === currentUser?.id) return;
  clearTimeout(timer);
  dirty = false;
  blocked = false;
  busy = false;
  revision = null;
  premium = false;
  message = '';
  currentUser = nextUser;
  if (!currentUser) {
    await bridge().switchAccount(null);
    setMessage('تم تسجيل الخروج. بيانات كل حساب تظل محفوظة بشكل منفصل.');
    return;
  }
  const userId = currentUser.id;
  try {
    await bridge().switchAccount(userId);
    setMessage('جاري تحميل بيانات حسابك…');
    const remote = await getRemote();
    if (currentUser?.id !== userId) return;
    const local = bridge().read();
    revision = remote?.revision ?? null;
    if (remote && hasFinancialData(remote.snapshot)) {
      if (!hasFinancialData(local)) {
        await guardedReplace(remote.snapshot);
      } else if (JSON.stringify(remote.snapshot) !== JSON.stringify(local)) {
        if (confirm('في بيانات مختلفة على الجهاز والسحابة. اضغط موافق لدمج المعاملات بدون حذف أي منها، أو إلغاء لإيقاف المزامنة مؤقتًا.')) {
          await guardedReplace(mergeSnapshots(remote.snapshot, local));
          dirty = true;
        } else {
          blocked = true;
        }
      }
    } else if (hasFinancialData(local)) {
      dirty = true;
    }
    const importKey = 'hesabaty_guest_import_prompted:' + userId;
    if (!blocked && !localStorage.getItem(importKey)) {
      const imported = await importGuest(false);
      localStorage.setItem(importKey, 'yes');
      if (imported) dirty = true;
    }
    await readPremium();
    if (!blocked && (dirty || !remote)) {
      dirty = true;
      await push();
    } else {
      setMessage(blocked ? 'تم إيقاف المزامنة لحماية البيانات. اختار مزامنة الآن للمراجعة.'
        : '✓ بيانات حسابك جاهزة.');
    }
  } catch (error) {
    blocked = true;
    setMessage('تعذر الاتصال بقاعدة البيانات. بياناتك المحلية لم تُمس: ' + String(error?.message || error));
  }
}

async function syncNow() {
  if (!currentUser || busy) return;
  busy = true;
  try {
    const remote = await getRemote();
    const local = bridge().read();
    if (remote) {
      if (remote.revision !== revision || blocked) {
        if (hasFinancialData(local) && hasFinancialData(remote.snapshot)
          && JSON.stringify(local) !== JSON.stringify(remote.snapshot)) {
          if (!confirm('في اختلاف بين بيانات الجهاز والسحابة. ندمجهم معًا بدون حذف معاملات؟')) return;
          await guardedReplace(mergeSnapshots(remote.snapshot, local));
          dirty = true;
        } else if (!dirty && !hasFinancialData(local)) {
          await guardedReplace(remote.snapshot);
        }
      }
      revision = remote.revision;
    } else {
      revision = null;
    }
    blocked = false;
    dirty = dirty || !remote || JSON.stringify(bridge().read()) !== JSON.stringify(remote.snapshot);
    setMessage('جاري تحديث المزامنة…');
  } catch (error) {
    blocked = true;
    setMessage('فشل الاتصال: ' + String(error?.message || error));
  } finally {
    busy = false;
  }
  if (dirty && !blocked) await push();
  else if (!blocked) setMessage('✓ بيانات جهازك والسحابة متزامنة.');
}

async function onAuthAction(action) {
  try {
    if (action === 'google') {
      if (window.Capacitor?.isNativePlatform?.()) {
        setMessage('تسجيل Google داخل أندرويد يحتاج ربط المتصفح الخارجي والعودة للتطبيق. استخدم الإيميل مؤقتًا.');
        return;
      }
      const { error } = await client.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: location.origin + location.pathname }
      });
      if (error) throw error;
      return;
    }
    if (action === 'signout') {
      if (dirty) await syncNow();
      if (dirty || blocked) {
        if (!confirm('بعض التغييرات غير محفوظة بالسحابة، لكنها باقية على الجهاز. هل تريد تسجيل الخروج؟')) return;
      }
      const { error } = await client.auth.signOut();
      if (error) throw error;
      await connectSession(null);
      return;
    }
    if (action === 'sync') return await syncNow();
    if (action === 'import-guest') {
      if (await importGuest()) queuePush();
      return;
    }
    const email = document.getElementById('hesabatyEmail')?.value.trim() || '';
    const password = document.getElementById('hesabatyPassword')?.value || '';
    if (!email || password.length < 6) {
      setMessage('اكتب إيميل صحيح وكلمة مرور 6 أحرف على الأقل.');
      return;
    }
    setMessage('جاري تأمين تسجيل الدخول…');
    const result = action === 'signup'
      ? await client.auth.signUp({ email, password })
      : await client.auth.signInWithPassword({ email, password });
    if (result.error) throw result.error;
    if (action === 'signup' && !result.data.session) {
      setMessage('الحساب اتعمل. افتح رسالة تأكيد الإيميل، وبعدها سجل دخول.');
    }
  } catch (error) {
    setMessage('تعذر إكمال الطلب: ' + String(error?.message || error));
  }
}

window.hesabatyCloud = { panel, changed: queuePush };

document.addEventListener('submit', event => {
  if (event.target.id !== 'hesabatyCloudForm') return;
  event.preventDefault();
  if (!client) return;
  void onAuthAction(event.submitter?.value === 'signup' ? 'signup' : 'signin');
});
document.addEventListener('click', event => {
  const button = event.target.closest('[data-cloud]');
  if (button && client) void onAuthAction(button.dataset.cloud);
});

if (configured) {
  try {
    client = createClient(settings.url, settings.publishableKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce', storageKey: 'hesabaty-auth' }
    });
    void (async () => {
      await bridge().ready;
      const result = await client.auth.getSession();
      if (result.error) throw result.error;
      await connectSession(result.data.session);
      client.auth.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') {
          setTimeout(() => void connectSession(session), 0);
        }
      });
    })().catch(error => setMessage('تعذر بدء تسجيل الدخول: ' + String(error?.message || error)));
  } catch (error) {
    message = 'إعدادات Supabase غير صحيحة: ' + String(error?.message || error);
  }
}
refresh();
