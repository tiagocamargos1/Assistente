// Assistente Pessoal — service worker
// Handles: basic app-shell caching (fast/offline opening) + Web Push delivery.
const CACHE_NAME = 'assistente-shell-v2';
const SHELL_FILES = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).catch(() => {})
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const isSameOrigin = event.request.url.startsWith(self.location.origin);
  // Network-first: every load tries the network first (bypassing the HTTP
  // cache entirely via cache:'no-store'), so a fresh deploy shows up on the
  // very next reload. Only falls back to the cached copy if the network
  // request fails (offline). The old strategy served the cached copy
  // instantly and only refreshed the cache in the background — correct for
  // offline support, but it meant every reload was always one version
  // behind whatever was just published, which is what made updates look
  // like they "never arrive" on Mac/web.
  event.respondWith(
    fetch(event.request, { cache: 'no-store' })
      .then((resp) => {
        if (resp && resp.ok && isSameOrigin) {
          const copy = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return resp;
      })
      .catch(() => caches.match(event.request))
  );
});

// ── Web Push ──────────────────────────────────────
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: '🔔 Assistente Pessoal', body: event.data ? event.data.text() : 'Você tem novidades.' };
  }
  const title = data.title || '🔔 Assistente Pessoal';
  const options = {
    body: data.body || '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    data: { url: data.url || './' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
