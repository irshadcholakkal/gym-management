// Generated cache version must change on EVERY deployment (tool/build_web.ps1).
const CACHE = 'gympro-shell-development-v1';
const BASE = new URL('./', self.location.href);
const ASSETS = ['index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
  'manifest.json', 'favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png',
  'assets/AssetManifest.bin.json', 'assets/FontManifest.json', 'assets/NOTICES',
  'assets/fonts/MaterialIcons-Regular.otf', 'sqlite3.wasm', 'drift_worker.dart.js',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS.map(p => new URL(p, BASE).href))));
  // The waiting worker is activated only by an explicit UI update action.
});
self.addEventListener('message', event => {
  if (event.data?.type === 'ACTIVATE_UPDATE') self.skipWaiting();
});
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys()) if (key.startsWith('gympro-shell-') && key !== CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== BASE.origin) return;
  // Only public, explicit app-shell assets are cached. No API/auth responses.
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match(new URL('index.html', BASE).href)));
  } else if (ASSETS.some(p => url.href === new URL(p, BASE).href)) {
    event.respondWith(caches.match(event.request).then(hit => hit || fetch(event.request)));
  }
});
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data?.json() || {}; } catch (_) { /* Legacy or empty push. */ }
  const id = /^[a-f0-9-]{36}$/i.test(payload.notification_id || '') ? payload.notification_id : null;
  const gym = /^[a-f0-9-]{36}$/i.test(payload.gym_id || '') ? payload.gym_id : null;
  const route = new URL('./', BASE);
  const query = new URLSearchParams();
  if (id) query.set('notification', id);
  if (gym) query.set('gym', gym);
  route.hash = '/notifications' + (query.size ? '?' + query.toString() : '');
  // Never put member names or contact details on the lock screen.
  const messages = {
    expiry_7: 'A membership expires in 7 days. Review the renewal reminder.',
    expiry_3: 'A membership expires in 3 days. Review the renewal reminder.',
    expiry_1: 'A membership expires tomorrow. Review the renewal reminder.',
    expiry_0: 'A membership expires today. Review the warning.',
    expired: 'A membership has expired. Open your workspace to review.',
  };
  event.waitUntil(self.registration.showNotification('GymPro UAE', {
    body: messages[payload.type] || 'You have a gym update. Open your workspace to review.',
    icon: new URL('icons/Icon-192.png', BASE).href,
    tag: id ? 'gympro-' + id : 'gympro-update', data: { url: route.href },
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    let target = new URL('./#/notifications', BASE).href;
    try {
      const requested = new URL(event.notification.data?.url);
      if (requested.origin === BASE.origin && requested.pathname === BASE.pathname && requested.hash.startsWith('#/notifications')) target = requested.href;
    } catch (_) { /* Fall back to inbox. */ }
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(w => new URL(w.url).origin === BASE.origin && new URL(w.url).pathname.startsWith(BASE.pathname));
    if (existing) {
      try { await existing.navigate(target); await existing.focus(); }
      catch (_) { await self.clients.openWindow(target); }
    }
    else await self.clients.openWindow(target);
  })());
});
