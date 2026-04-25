// ============================================================
//  Oswald Vision Capital — Service Worker
//  Strategy: Cache-first for static assets, network-first for HTML/JS
// ============================================================

var CACHE_NAME = 'ovc-v6';
// JS files intentionally excluded — always fetch fresh (contain live data logic)
var STATIC_ASSETS = [
  '/oswaldvisioncapital/manifest.json'
];

// Install: pre-cache static shell
self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(STATIC_ASSETS).catch(function (err) {
        console.warn('[SW] Pre-cache partial failure:', err);
      });
    })
  );
  self.skipWaiting();
});

// Activate: purge ALL old caches, claim clients immediately
self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys
          .filter(function (key) { return key !== CACHE_NAME; })
          .map(function (key) { return caches.delete(key); })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

// Helper: safely clone and cache a response — never throws
function safePut(request, response) {
  try {
    var clone = response.clone();
    caches.open(CACHE_NAME).then(function (cache) {
      cache.put(request, clone).catch(function () {});
    });
  } catch (e) {}
}

// Fetch handler
self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);

  // Skip non-GET
  if (event.request.method !== 'GET') return;

  // Skip external APIs and CDNs — let them go direct
  if (url.hostname.includes('supabase') ||
      url.hostname.includes('yahoo') ||
      url.hostname.includes('frankfurter') ||
      url.hostname.includes('jsdelivr') ||
      url.hostname.includes('cdn')) return;

  // Google Fonts: cache-first (immutable)
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(
      caches.match(event.request).then(function (cached) {
        if (cached) return cached;
        return fetch(event.request).then(function (response) {
          if (response.ok) safePut(event.request, response);
          return response;
        });
      })
    );
    return;
  }

  // JS files: always network-first, no caching
  if (url.pathname.endsWith('.js')) {
    event.respondWith(
      fetch(event.request).catch(function () {
        return caches.match(event.request);
      })
    );
    return;
  }

  // HTML pages: always network-first — cache only as offline fallback
  if (event.request.headers.get('accept') &&
      event.request.headers.get('accept').includes('text/html')) {
    event.respondWith(
      fetch(event.request)
        .then(function (response) {
          if (response.ok) safePut(event.request, response);
          return response;
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
        if (response.ok) safePut(event.request, response);
        return response;
      });
    })
  );
});
