// ============================================================
//  Oswald Vision Capital — Service Worker v2
//  Strategy: Cache-first for static assets, network-first for HTML
// ============================================================

var CACHE_NAME = 'ovc-v2';
var STATIC_ASSETS = [
  '/',
  '/index.html',
  '/analyses.html',
  '/performance.html',
  '/macro.html',
  '/mon-compte.html',
  '/mentions-legales.html',
  '/manifest.json',
  '/js/live.js',
  '/js/supabase-client.js'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(STATIC_ASSETS).catch(function () {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (key) { return key !== CACHE_NAME; })
            .map(function (key) { return caches.delete(key); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);
  if (event.request.method !== 'GET') return;
  if (url.hostname.includes('supabase') || url.hostname.includes('yahoo') ||
      url.hostname.includes('frankfurter') || url.hostname.includes('jsdelivr')) return;

  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(
      caches.match(event.request).then(function (c) {
        return c || fetch(event.request).then(function (r) {
          caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, r.clone()); });
          return r;
        });
      })
    );
    return;
  }

  if (event.request.headers.get('accept') && event.request.headers.get('accept').includes('text/html')) {
    event.respondWith(
      fetch(event.request)
        .then(function (r) {
          caches.open(CACHE_NAME).then(function (c) { c.put(event.request, r.clone()); });
          return r;
        })
        .catch(function () {
          return caches.match(event.request).then(function (c) {
            return c || caches.match('/index.html');
          });
        })
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(function (c) {
      if (c) return c;
      return fetch(event.request).then(function (r) {
        if (r.status === 200) {
          caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, r.clone()); });
        }
        return r;
      });
    })
  );
});
