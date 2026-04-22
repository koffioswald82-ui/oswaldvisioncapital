#!/usr/bin/env python3
"""
OVC — Automatic Portfolio Price Updater
Runs twice daily via GitHub Actions (after EU close + after US close)

Required GitHub Secrets:
  SUPABASE_URL         — ex: https://bnmjhmijhgxpjbrtwbdv.supabase.co
  SUPABASE_SERVICE_KEY — service role key (Supabase → Settings → API → service_role)
"""

import os
import sys
import json
import time
import requests
from datetime import datetime, timezone

# ── Config ────────────────────────────────────────────────
SUPABASE_URL = os.environ.get('SUPABASE_URL', '').strip().rstrip('/')
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_KEY', '').strip()
DRY_RUN      = os.environ.get('DRY_RUN', 'false').lower() == 'true'

if not SUPABASE_URL or not SUPABASE_KEY:
    print('[ERR] Missing SUPABASE_URL or SUPABASE_SERVICE_KEY')
    sys.exit(1)

SB_HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
    'Prefer':        'return=minimal'
}

# ── Supabase helpers ──────────────────────────────────────
def sb_get(table, query=''):
    r = requests.get(f'{SUPABASE_URL}/rest/v1/{table}{query}', headers=SB_HEADERS, timeout=15)
    r.raise_for_status()
    return r.json()

def sb_patch(table, data, where):
    if DRY_RUN:
        print(f'  [DRY] PATCH {table} {where} → {data}')
        return
    r = requests.patch(
        f'{SUPABASE_URL}/rest/v1/{table}?{where}',
        headers=SB_HEADERS, json=data, timeout=15
    )
    r.raise_for_status()

# ── Yahoo Finance via yfinance (gère cookies + auth) ─────
def yahoo_prices(symbols: list) -> dict:
    """Fetch prices using yfinance — handles Yahoo auth automatically."""
    if not symbols:
        return {}
    try:
        import yfinance as yf
        out = {}
        # Download all at once (most efficient)
        data = yf.download(
            tickers=symbols,
            period='2d',
            interval='1d',
            auto_adjust=True,
            progress=False,
            threads=True
        )
        if data.empty:
            print(f'  [yfinance] Empty response for {symbols}')
            return {}

        # Single ticker returns a simple DataFrame; multiple returns MultiIndex
        if len(symbols) == 1:
            sym = symbols[0]
            close = data['Close']
            if not close.empty:
                out[sym] = float(close.iloc[-1])
        else:
            close = data['Close']
            for sym in symbols:
                try:
                    val = close[sym].dropna()
                    if not val.empty:
                        out[sym] = float(val.iloc[-1])
                except Exception as e:
                    print(f'  [yfinance] {sym}: {e}')
        return out
    except Exception as exc:
        print(f'  [yfinance ERR] {exc}')
        # Fallback: try raw Yahoo v7 API
        return yahoo_prices_raw(symbols)

def yahoo_prices_raw(symbols: list) -> dict:
    """Fallback: raw Yahoo Finance v7 quote API."""
    if not symbols:
        return {}
    syms = ','.join(symbols)
    url  = (f'https://query1.finance.yahoo.com/v7/finance/quote'
            f'?symbols={syms}&fields=regularMarketPrice,currency,marketState')
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9',
    }
    try:
        r    = requests.get(url, headers=headers, timeout=15)
        data = r.json()
        out  = {}
        for q in data.get('quoteResponse', {}).get('result', []):
            sym   = q.get('symbol', '')
            price = q.get('regularMarketPrice')
            if sym and price is not None:
                out[sym] = float(price)
        return out
    except Exception as exc:
        print(f'  [Yahoo raw ERR] {syms}: {exc}')
        return {}

# ── yfinance historical data ──────────────────────────────
def yahoo_history(symbol: str, months: int = 13) -> list:
    """Returns list of {date, close} sorted ascending via yfinance."""
    try:
        import yfinance as yf
        tk   = yf.Ticker(symbol)
        hist = tk.history(period=f'{months}mo', interval='1wk', auto_adjust=True)
        out  = []
        for idx, row in hist.iterrows():
            if row['Close'] and not (row['Close'] != row['Close']):  # not NaN
                out.append({
                    'date':  idx.strftime('%Y-%m-%d'),
                    'close': round(float(row['Close']), 4)
                })
        return out
    except Exception as exc:
        print(f'  [hist ERR] {symbol}: {exc}')
        return []

# ── Frankfurter FX rates ──────────────────────────────────
def fetch_fx() -> dict:
    try:
        r    = requests.get(
            'https://api.frankfurter.app/latest?from=EUR&to=USD,GBP,HKD,JPY,CHF,CAD,SEK,KRW',
            timeout=10
        )
        data = r.json()
        rates = data.get('rates', {})
        return {k: round(1 / v, 6) for k, v in rates.items() if v}
    except Exception as exc:
        print(f'  [FX ERR] {exc}')
        return {}

# ── Benchmark upsert ──────────────────────────────────────
def store_benchmark(symbol: str, label: str):
    rows = yahoo_history(symbol)
    if not rows:
        print(f'  [Bench] No data for {symbol}')
        return
    base = rows[0]['close']
    for row in rows:
        row['symbol'] = symbol
        row['label']  = label
        row['value']  = round(row['close'] / base * 100, 4)
    if DRY_RUN:
        print(f'  [DRY] Would upsert {len(rows)} rows for {symbol}')
        return
    batch_size = 50
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        r = requests.post(
            f'{SUPABASE_URL}/rest/v1/benchmark_history',
            headers={**SB_HEADERS, 'Prefer': 'resolution=merge-duplicates'},
            json=batch, timeout=20
        )
        if r.status_code not in (200, 201):
            print(f'  [Bench ERR] {r.status_code}: {r.text[:200]}')
    print(f'  [Bench] {symbol} ({label}): {len(rows)} points upserted')

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════
def main():
    now = datetime.now(timezone.utc).isoformat()
    print(f'{"="*55}')
    print(f'OVC Price Updater — {now}{"  [DRY RUN]" if DRY_RUN else ""}')
    print(f'{"="*55}')

    # 1. Fetch portfolio from Supabase
    positions = sb_get('portfolio', '?select=ticker,name,current_price,currency,api_method')
    if not positions:
        print('[WARN] Portfolio vide dans Supabase — rien à mettre à jour.')
        print('       → Vérifiez que les positions sont bien sauvegardées dans Supabase (pas seulement en localStorage).')
        return

    print(f'[Portfolio] {len(positions)} positions trouvées')

    # 2. Sort by method
    yahoo_tickers, brvm_tickers, manual_tickers = [], [], []
    for p in positions:
        m = (p.get('api_method') or 'yahoo').lower()
        t = p.get('ticker', '')
        if m == 'manual':
            manual_tickers.append(t)
        elif 'brvm' in m:
            brvm_tickers.append(t)
        else:
            yahoo_tickers.append(t)

    print(f'  Yahoo : {yahoo_tickers or "aucun"}')
    print(f'  BRVM  : {brvm_tickers  or "aucun"}')
    print(f'  Manuel: {manual_tickers or "aucun"}')

    # 3. Fetch Yahoo prices via yfinance (batches of 15)
    prices = {}
    for i in range(0, len(yahoo_tickers), 15):
        chunk   = yahoo_tickers[i:i + 15]
        fetched = yahoo_prices(chunk)
        prices.update(fetched)
        time.sleep(0.8)

    # 4. BRVM — try Yahoo with .BV suffix, then raw
    for t in brvm_tickers:
        sym = t + '.BV'
        p   = yahoo_prices([sym])
        if p.get(sym):
            prices[t] = p[sym]
            print(f'  [BRVM] {t} → {sym}: {p[sym]}')
        else:
            print(f'  [BRVM] {t}: non trouvé sur Yahoo, prix inchangé')

    # 5. Update Supabase portfolio
    updated = skipped = errors = 0
    for pos in positions:
        t      = pos['ticker']
        method = (pos.get('api_method') or 'yahoo').lower()
        if method == 'manual':
            skipped += 1
            continue
        new_p = prices.get(t)
        if new_p is None:
            print(f'  [MISS] {t}: pas de prix trouvé')
            skipped += 1
            continue
        old_p = float(pos.get('current_price') or 0)
        chg   = ((new_p - old_p) / old_p * 100) if old_p else 0
        flag  = 'DRY' if DRY_RUN else 'OK '
        print(f'  [{flag}] {t:14s}  {old_p:10.4f} → {new_p:10.4f}  ({chg:+.2f}%)')
        try:
            sb_patch('portfolio', {'current_price': new_p}, f'ticker=eq.{t}')
            updated += 1
        except Exception as exc:
            print(f'  [ERR] {t}: {exc}')
            errors += 1
        time.sleep(0.1)

    # 6. FX rates → fund_settings.fx_rates
    print('\n[FX] Récupération des taux de change…')
    fx = fetch_fx()
    if fx:
        fx_payload = {**fx, 'XOF': 0.0015245, 'EUR': 1.0, 'updated_at': now}
        print(f'  Taux : {fx_payload}')
        try:
            sb_patch('fund_settings', {'fx_rates': json.dumps(fx_payload)}, 'id=eq.1')
            print('  [OK] FX rates stockés dans fund_settings.fx_rates')
        except Exception as exc:
            print(f'  [WARN] FX non stockés : {exc}')

    # 7. Benchmark history
    print('\n[Benchmark] Historique hebdomadaire…')
    store_benchmark('^GSPC',     'S&P 500')
    store_benchmark('^STOXX50E', 'Euro Stoxx 50')

    # 8. Summary
    print(f'\n{"="*55}')
    print(f'Mis à jour : {updated}  |  Ignorés : {skipped}  |  Erreurs : {errors}')
    print(f'Terminé    : {datetime.now(timezone.utc).isoformat()}')
    if errors:
        sys.exit(1)

if __name__ == '__main__':
    main()
