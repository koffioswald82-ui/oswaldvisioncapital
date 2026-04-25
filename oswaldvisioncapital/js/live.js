// ============================================================
//  Oswald Vision Capital — Live Data Module (live.js)
//  Populates .ticker-inner and .hero-proof with real data.
//  Requires window._db (initialized by supabase-client.js)
// ============================================================
(function () {
  'use strict';

  // ── Helpers ──────────────────────────────────────────────

  function fmt(num, decimals) {
    if (num == null || isNaN(num)) return '—';
    return Number(num).toFixed(decimals != null ? decimals : 2);
  }

  function pctClass(pct) {
    return pct >= 0 ? 'up' : 'dn';
  }

  function pctStr(pct) {
    var sign = pct >= 0 ? '+' : '';
    return sign + fmt(pct, 2) + '%';
  }

  // Animated counter: counts from 0 to target over ~1500ms
  function animateCounter(el, target, decimals, suffix) {
    if (!el) return;
    var start = null;
    var duration = 1500;
    var dec = decimals || 0;
    var suf = suffix || '';

    function step(ts) {
      if (!start) start = ts;
      var progress = Math.min((ts - start) / duration, 1);
      // Ease out cubic
      var ease = 1 - Math.pow(1 - progress, 3);
      var current = ease * target;
      el.textContent = fmt(current, dec) + suf;
      if (progress < 1) requestAnimationFrame(step);
      else el.textContent = fmt(target, dec) + suf;
    }
    requestAnimationFrame(step);
  }

  // ── NAV History (shared) ──────────────────────────────────

  var _navCache = null; // { nav, date }
  var NAV_LAUNCH = 100;

  var FX_DEFAULTS = { USD:0.855139, EUR:1, GBP:1.155068, KRW:0.000578, HKD:0.10917, CHF:1.089681, CAD:0.625547, JPY:0.005362 };

  function fetchLatestNav() {
    return new Promise(function (resolve) {
      if (!window._db) { resolve(null); return; }
      try {
        window._db
          .from('nav_history')
          .select('nav,date')
          .order('date', { ascending: false })
          .limit(1)
          .then(function (res) {
            if (res && res.data && res.data.length) {
              _navCache = res.data[0];
              resolve(_navCache);
            } else {
              resolve(null);
            }
          })
          .catch(function () { resolve(null); });
      } catch (e) {
        resolve(null);
      }
    });
  }

  // Fallback: compute live NAV from fund_settings + portfolio when nav_history is empty
  function computeNavLive() {
    if (!window._db) return Promise.resolve(null);
    return Promise.all([
      window._db.from('fund_settings').select('cash,parts,fx_rates').eq('id', 1).maybeSingle(),
      window._db.from('portfolio').select('qty,current_price,currency')
    ]).then(function (results) {
      var fsRes = results[0]; var portRes = results[1];
      var fs = fsRes && fsRes.data;
      var positions = (portRes && portRes.data) || [];
      if (!fs || !(parseFloat(fs.parts) > 0)) return null;
      var fx = Object.assign({}, FX_DEFAULTS);
      try {
        var stored = typeof fs.fx_rates === 'string' ? JSON.parse(fs.fx_rates) : (fs.fx_rates || {});
        Object.keys(stored).forEach(function (k) { if (typeof stored[k] === 'number') fx[k] = stored[k]; });
      } catch (e) {}
      var posVal = 0;
      positions.forEach(function (p) {
        posVal += (parseFloat(p.qty) || 0) * (parseFloat(p.current_price) || 0) * (fx[p.currency] || 1);
      });
      var nav = (parseFloat(fs.cash) + posVal) / parseFloat(fs.parts);
      if (isNaN(nav) || nav <= 0) return null;
      return { nav: parseFloat(nav.toFixed(4)), date: null, computed: true };
    }).catch(function () { return null; });
  }

  function fetchNavWithFallback() {
    return fetchLatestNav().then(function (navData) {
      if (navData) return navData;
      return computeNavLive();
    });
  }

  // ── TICKER ────────────────────────────────────────────────

  function buildTickerItem(ticker, name, price, currency, pct) {
    var cls = pctClass(pct);
    return (
      '<span class="ti">' +
        '<span class="ti-s">' + ticker + '</span>' +
        name +
        ' <span class="' + cls + '">' + fmt(price, 2) + ' ' + currency + '</span>' +
        ' <span class="' + cls + '">' + pctStr(pct) + '</span>' +
      '</span> · '
    );
  }

  function buildNavItem(nav, pct) {
    var cls = pctClass(pct);
    return (
      '<span class="ti">' +
        '<span class="ti-s">OVC</span>' +
        'Oswald Vision Capital' +
        ' <span class="' + cls + '">' + fmt(nav, 2) + ' EUR</span>' +
        ' <span class="' + cls + '">' + pctStr(pct) + '</span>' +
      '</span> · '
    );
  }

  function buildIndexItem(symbol, label, price, pct) {
    var cls = pctClass(pct);
    return (
      '<span class="ti">' +
        '<span class="ti-s">' + symbol + '</span>' +
        label +
        ' <span class="' + cls + '">' + fmt(price, 2) + '</span>' +
        ' <span class="' + cls + '">' + pctStr(pct) + '</span>' +
      '</span> · '
    );
  }

  function refreshTicker() {
    var inner = document.querySelector('.ticker-inner');
    if (!inner) return;

    var navPromise = fetchNavWithFallback();

    var portfolioPromise = new Promise(function (resolve) {
      if (!window._db) { resolve([]); return; }
      try {
        window._db
          .from('portfolio')
          .select('ticker,name,current_price,entry_price,currency')
          .then(function (res) {
            resolve((res && res.data) ? res.data : []);
          })
          .catch(function () { resolve([]); });
      } catch (e) {
        resolve([]);
      }
    });

    // Try Yahoo Finance for S&P500 + CAC40 (CORS may block — fail silently)
    var indicesPromise = new Promise(function (resolve) {
      try {
        var url = 'https://query1.finance.yahoo.com/v7/finance/quote?symbols=%5EGSPC,%5EFCHI';
        fetch(url, { mode: 'cors', cache: 'no-cache' })
          .then(function (r) { return r.json(); })
          .then(function (data) {
            var results = [];
            try {
              var quotes = data.quoteResponse.result;
              if (quotes && quotes.length) {
                quotes.forEach(function (q) {
                  results.push({
                    symbol: q.symbol === '^GSPC' ? 'S&P500' : 'CAC40',
                    label: q.symbol === '^GSPC' ? 'S&P 500' : 'CAC 40',
                    price: q.regularMarketPrice,
                    pct: q.regularMarketChangePercent
                  });
                });
              }
            } catch (e) {}
            resolve(results);
          })
          .catch(function () { resolve([]); });
      } catch (e) {
        resolve([]);
      }
    });

    Promise.all([navPromise, portfolioPromise, indicesPromise]).then(function (results) {
      var navData = results[0];
      var positions = results[1];
      var indices = results[2];

      var html = '';

      // NAV item
      if (navData && navData.nav) {
        // We don't have prior NAV for % change from this query alone — show NAV flat
        // If we had 2 rows we could compute, but limit(1) gives current only
        html += buildNavItem(navData.nav, 0);
      }

      // Index items
      if (indices && indices.length) {
        indices.forEach(function (idx) {
          html += buildIndexItem(idx.symbol, idx.label, idx.price, idx.pct);
        });
      }

      // Portfolio positions
      positions.forEach(function (pos) {
        var pct = 0;
        if (pos.entry_price && pos.current_price && pos.entry_price !== 0) {
          pct = ((pos.current_price - pos.entry_price) / pos.entry_price) * 100;
        }
        html += buildTickerItem(
          pos.ticker,
          pos.name,
          pos.current_price || 0,
          pos.currency || 'EUR',
          pct
        );
      });

      if (!html) return; // nothing to replace

      // Duplicate for infinite scroll (CSS uses -50% translate)
      inner.innerHTML = html + html;
    });
  }

  // ── HERO STATS ────────────────────────────────────────────

  function refreshHeroStats() {
    // --- Articles count ---
    var articlesPromise = new Promise(function (resolve) {
      if (!window._db) { resolve(0); return; }
      try {
        window._db
          .from('articles')
          .select('slug', { count: 'exact', head: true })
          .eq('published', true)
          .then(function (res) {
            resolve((res && res.count != null) ? res.count : 0);
          })
          .catch(function () { resolve(0); });
      } catch (e) {
        resolve(0);
      }
    });

    // --- Subscribers count (may fail if no public read policy) ---
    var subsPromise = new Promise(function (resolve) {
      if (!window._db) { resolve(0); return; }
      try {
        window._db
          .from('subscribers')
          .select('id', { count: 'exact', head: true })
          .then(function (res) {
            resolve((res && res.count != null) ? res.count : 0);
          })
          .catch(function () { resolve(0); });
      } catch (e) {
        resolve(0);
      }
    });

    // --- Latest NAV ---
    var navPromise = fetchNavWithFallback();

    Promise.all([articlesPromise, subsPromise, navPromise]).then(function (results) {
      var articleCount = results[0];
      var subCount = results[1];
      var navData = results[2];

      // live-nav: current NAV value
      var elNav = document.getElementById('live-nav');
      if (elNav && navData && navData.nav) {
        animateCounter(elNav, navData.nav, 2, '');
      }

      // live-perf: performance % since inception (base NAV_LAUNCH = 100)
      var elPerf = document.getElementById('live-perf');
      if (elPerf && navData && navData.nav) {
        if (window._db) {
          try {
            window._db
              .from('nav_history')
              .select('nav,date')
              .order('date', { ascending: true })
              .limit(1)
              .then(function (res) {
                var firstNav = (res && res.data && res.data.length) ? parseFloat(res.data[0].nav) : NAV_LAUNCH;
                if (!firstNav || firstNav <= 0) firstNav = NAV_LAUNCH;
                var perf = ((navData.nav - firstNav) / firstNav) * 100;
                animateCounter(elPerf, perf, 2, '%');
              })
              .catch(function () {
                var perf = ((navData.nav - NAV_LAUNCH) / NAV_LAUNCH) * 100;
                animateCounter(elPerf, perf, 2, '%');
              });
          } catch (e) {
            var perf = ((navData.nav - NAV_LAUNCH) / NAV_LAUNCH) * 100;
            animateCounter(elPerf, perf, 2, '%');
          }
        } else {
          var perf = ((navData.nav - NAV_LAUNCH) / NAV_LAUNCH) * 100;
          animateCounter(elPerf, perf, 2, '%');
        }
      }

      // live-articles: article count
      var elArticles = document.getElementById('live-articles');
      if (elArticles && articleCount > 0) {
        animateCounter(elArticles, articleCount, 0, '');
      }

      // live-subs: subscriber count
      var elSubs = document.getElementById('live-subs');
      if (elSubs && subCount > 0) {
        animateCounter(elSubs, subCount, 0, '');
      }
    });
  }

  // ── Init ──────────────────────────────────────────────────

  function init() {
    refreshTicker();
    refreshHeroStats();

    // Refresh ticker every 5 minutes
    setInterval(refreshTicker, 5 * 60 * 1000);
  }

  // ── Expose ────────────────────────────────────────────────

  window.OVCLive = { init: init };

  // Auto-init on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
