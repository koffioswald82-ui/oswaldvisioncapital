// ============================================================
//  Oswald Vision Capital — Service Worker
//  Strategy: Cache-first for static assets, network-first for HTML
// ============================================================

var CACHE_NAME = 'ovc-v5';
// JS files intentionally excluded — always fetch fresh (contain live data logic)
var STATIC_ASSETS = [
  '/oswaldvisioncapital/manifest.json'
];

// Install: pre-cache static shell
self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(STATIC_ASSETS).catch(function (err) {
        // Non-fatal: some assets may not exist yet
        console.warn('[SW] Pre-cache partial failure:', err);
      });
    })
  );
  self.skipWaiting();
});

// Activate: purge old caches
self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys
          .filter(function (key) { return key !== CACHE_NAME; })
          .map(function (key) { return caches.delete(key); })
      );
    })
  );
  self.clients.claim();
});

// Fetch handler
self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);

  // Skip non-GET and external API calls
  if (event.request.method !== 'GET') return;
  if (url.hostname.includes('supabase') ||
      url.hostname.includes('yahoo') ||
      url.hostname.includes('frankfurter') ||
      url.hostname.includes('jsdelivr') ||
      url.hostname.includes('cdn')) return;

  // Google Fonts: cache-first (never changes)
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(
      caches.match(event.request).then(function (cached) {
        return cached || fetch(event.request).then(function (response) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
          return response;
        });
      })
    );
    return;
  }

  // JS files: always network-first, no caching (live data logic changes often)
  if (url.pathname.endsWith('.js')) {
    event.respondWith(
      fetch(event.request).catch(function () {
        return caches.match(event.request);
      })
    );
    return;
  }

  // HTML pages: network-first, always serve fresh — cache only as offline fallback
  if (event.request.headers.get('accept') &&
      event.request.headers.get('accept').includes('text/html')) {
    event.respondWith(
      fetch(event.request)
        .then(function (response) {
          try {
            var clone = response.clone();
            caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
          } catch(e) {}
          return response; // always return fresh response, even if caching fails
        })
        .catch(function () {
          return caches.match(event.request).then(function (cached) {
            return cached || caches.match('/oswaldvisioncapital/index.html');
          });
        })
    );
    return;
  }

  // Other static assets (CSS, images): cache-first
  event.respondWith(
    caches.match(event.request).then(function (cached) {
      if (cached) return cached;
      return fetch(event.request).then(function (response) {
        if (response.status === 200) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
        }
        return response;
      });
    })
  );
});
