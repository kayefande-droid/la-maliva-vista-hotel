/* ============================================================
   LA-MALIVA VISTA - Offline-First Service Worker
   Strategy:
     - App shell + CDN assets : precached at install
     - Static assets          : stale-while-revalidate
     - GET pages              : network-first, cache fallback
     - POST/PUT/payments      : always network (never cached)
     - Offline fallback       : /offline page + cached shell
   ============================================================ */

const VERSION = 'v2.3.0';
const SHELL_CACHE = 'lmv-shell-' + VERSION;
const PAGES_CACHE = 'lmv-pages-' + VERSION;
const ASSETS_CACHE = 'lmv-assets-' + VERSION;
const MAX_PAGES = 30;

const SHELL_ASSETS = [
  '/offline',
  '/static/logo.png',
  '/static/css/luxury.css',
  '/static/vendor/css/bootstrap.min.css',
  '/static/vendor/css/bootstrap-icons.css',
  '/static/vendor/css/bootstrap-icons.woff2',
  '/static/vendor/css/bootstrap-icons.woff',
  '/static/vendor/js/bootstrap.bundle.min.js',
  '/static/vendor/js/chart.umd.min.js'
];

const OFFLINE_URLS = ['/', '/login', '/signup', '/downloads'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const shell = await caches.open(SHELL_CACHE);
      // Cache shell items individually - one 404 must not abort the install
      await Promise.allSettled(
        SHELL_ASSETS.map((url) => shell.add(new Request(url, { cache: 'reload' })))
      );
      const pages = await caches.open(PAGES_CACHE);
      await Promise.allSettled(
        OFFLINE_URLS.map((url) => pages.add(new Request(url, { cache: 'reload' })))
      );
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keep = [SHELL_CACHE, PAGES_CACHE, ASSETS_CACHE];
      const names = await caches.keys();
      await Promise.all(names.map((n) => (keep.includes(n) ? null : caches.delete(n))));
      await self.clients.claim();
    })()
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

/* ---------------- Helpers ---------------- */

async function trimCache(cacheName, maxItems) {
  const cache = await caches.open(cacheName);
  const keys = await cache.keys();
  if (keys.length > maxItems) {
    await cache.delete(keys[0]);
    return trimCache(cacheName, maxItems);
  }
}

function isStaticAsset(url) {
  return (
    url.pathname.startsWith('/static/') ||
    url.hostname === 'cdn.jsdelivr.net' ||
    url.hostname === 'cdnjs.cloudflare.com' ||
    url.hostname === 'fonts.googleapis.com' ||
    url.hostname === 'fonts.gstatic.com' ||
    url.hostname === 'images.unsplash.com'
  );
}

/* ---------------- Fetch strategies ---------------- */

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return; // payments/forms always hit the network

  const url = new URL(request.url);
  if (url.origin !== self.location.origin && !isStaticAsset(url)) return;
  if (url.pathname.startsWith('/sw.js')) return;
  // NEVER cache the connectivity probe — the banner must reflect real reachability
  if (url.pathname === '/static/ping.txt') return;

  // 1) Static + CDN assets: stale-while-revalidate
  if (isStaticAsset(url)) {
    event.respondWith(
      (async () => {
        const cache = await caches.open(ASSETS_CACHE);
        const cached = await cache.match(request);
        const network = fetch(request)
          .then((response) => {
            if (response && (response.ok || response.type === 'opaque')) {
              cache.put(request, response.clone());
            }
            return response;
          })
          .catch(() => null);
        return cached || (await network) || Response.error();
      })()
    );
    return;
  }

  // 2) Navigations: network-first with cache fallback + offline page
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const response = await fetch(request);
          const cache = await caches.open(PAGES_CACHE);
          cache.put(request, response.clone());
          trimCache(PAGES_CACHE, MAX_PAGES);
          return response;
        } catch (err) {
          const cache = await caches.open(PAGES_CACHE);
          const cached = await cache.match(request, { ignoreSearch: true });
          if (cached) return cached;
          const shell = await caches.open(SHELL_CACHE);
          const offline = (await shell.match('/offline')) || (await cache.match('/'));
          if (offline) return offline;
          return new Response('<h1>You are offline</h1>', {
            headers: { 'Content-Type': 'text/html' },
            status: 503
          });
        }
      })()
    );
  }
});
