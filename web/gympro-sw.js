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
  // Generic lock-screen message; never render member details from push data.
  event.waitUntil(self.registration.showNotification('GymPro UAE', {
    body: 'You have a gym update. Open your workspace to review.',
    icon: new URL('icons/Icon-192.png', BASE).href,
    tag: 'gympro-update', data: { url: new URL('./#/notifications', BASE).href },
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const target = new URL('./#/notifications', BASE).href;
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(w => new URL(w.url).origin === BASE.origin);
    if (existing) { await existing.navigate(target); await existing.focus(); }
    else await self.clients.openWindow(target);
  })());
});
