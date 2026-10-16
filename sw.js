/* Network-first app shell: online changes become available without reinstalling the APK; offline fallback remains cached. Financial data stays in IndexedDB. */
const CACHE='hesabaty-shell-1.2.2';
const ASSETS=['./','./index.html','./app.js?v=1.2.1','./theme.js?v=1.2.1','./i18n.js?v=1.2.1','./styles.css?v=1.2.2','./manifest.webmanifest','./icons/icon-192.png','./icons/icon-512.png','./icons/icon-180.png'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('hesabaty-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',event=>{if(event.request.method!=='GET')return;const url=new URL(event.request.url);if(url.origin!==location.origin)return;event.respondWith(fetch(event.request).then(res=>{if(res.ok){const copy=res.clone();event.waitUntil(caches.open(CACHE).then(c=>c.put(event.request,copy)))}return res}).catch(()=>caches.match(event.request)))});
