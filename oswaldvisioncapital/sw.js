// ============================================================
//  Oswald Vision Capital — Service Worker
//  Strategy: Cache-first for static assets, network-first for HTML
// ============================================================

var CACHE_NAME = 'ovc-v3';
var STATIC_ASSETS = [
  '/oswaldvisioncapital/index.html',
  '/oswaldvisioncapital/analyses.html',
  '/oswaldvisioncapital/performance.html',
  '/oswaldvisioncapital/macro.html',
  '/oswaldvisioncapital/mon-compte.html',
  '/oswaldvisioncapital/mentions-legales.html',
  '/oswaldvisioncapital/manifest.json',
  '/oswaldvisioncapital/js/live.js',
  '/oswaldvisioncapital/js/supabase-client.js'
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

// Fetch: network-first for HTML/API, cache-first for fonts/JS/CSS
self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);

  // Skip non-GET and cross-origin API calls (Supabase, Yahoo Finance)
  if (event.request.method !== 'GET') return;
  if (url.hostname.includes('supabase') ||
      url.hostname.includes('yahoo') ||
      url.hostname.includes('frankfurter')) return;

  // Google Fonts: cache-first (very stable)
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

  // HTML pages: network-first with cache fallback
  if (event.request.headers.get('accept') &&
      event.request.headers.get('accept').includes('text/html')) {
    event.respondWith(
      fetch(event.request)
        .then(function (response) {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, clone); });
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

  // Static assets (JS, CSS, images): cache-first
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
