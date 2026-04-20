#!/usr/bin/env python3
"""
OVC — Automatic Portfolio Price Updater
Runs twice daily via GitHub Actions (after EU close + after US close)

Required GitHub Secrets:
  SUPABASE_URL         — ex: https://bnmjhmijhgxpjbrtwbdv.supabase.co
  SUPABASE_SERVICE_KEY — service role key (Settings → API → service_role)
"""

import os
import sys
import json
import time
import requests
from datetime import datetime, timezone

# ── Config
SUPABASE_URL = os.environ.get('SUPABASE_URL', '').rstrip('/')
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_KEY', '')
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
YF_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
}

# ── Supabase helpers
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

# ── Yahoo Finance: fetch up to 20 symbols at once
def yahoo_prices(symbols: list[str]) -> dict:
    if not symbols:
        return {}
    syms = ','.join(symbols)
    url  = (f'https://query1.finance.yahoo.com/v7/finance/quote'
            f'?symbols={syms}&fields=regularMarketPrice,currency,marketState')
    try:
        r    = requests.get(url, headers=YF_HEADERS, timeout=15)
        data = r.json()
        out  = {}
        for q in data.get('quoteResponse', {}).get('result', []):
            sym   = q.get('symbol', '')
            price = q.get('regularMarketPrice')
            if sym and price is not None:
                out[sym] = float(price)
        return out
    except Exception as exc:
        print(f'  [Yahoo ERR] {syms}: {exc}')
        return {}

# ── Yahoo Finance historical (for benchmark)
def yahoo_history(symbol: str, months: int = 13) -> list[dict]:
    """Returns list of {date, close} sorted ascending."""
    period = f'{months}mo'
    url = (f'https://query1.finance.yahoo.com/v8/finance/chart/{symbol}'
           f'?interval=1wk&range={period}')
    try:
        r    = requests.get(url, headers=YF_HEADERS, timeout=15)
        data = r.json()
        res  = data['chart']['result'][0]
        ts   = res['timestamp']
        closes = res['indicators']['quote'][0]['close']
        out = []
        for t, c in zip(ts, closes):
            if c is not None:
                out.append({
                    'date':  datetime.fromtimestamp(t, tz=timezone.utc).strftime('%Y-%m-%d'),
                    'close': round(float(c), 4)
                })
        return out
    except Exception as exc:
        print(f'  [Yahoo hist ERR] {symbol}: {exc}')
        return []

# ── Frankfurter FX rates
def fetch_fx() -> dict:
    try:
        r    = requests.get('https://api.frankfurter.app/latest?from=EUR&to=USD,GBP,HKD,JPY,CHF,CAD,SEK', timeout=10)
        data = r.json()
        rates = data.get('rates', {})
        # Invert: how many EUR per 1 unit of currency
        return {k: round(1 / v, 6) for k, v in rates.items() if v}
    except Exception as exc:
        print(f'  [FX ERR] {exc}')
        return {}

# ── Benchmark storage
def store_benchmark(symbol: str, label: str):
    """Upsert benchmark weekly history into Supabase benchmark_history table."""
    rows = yahoo_history(symbol)
    if not rows:
        print(f'  [Bench] No data for {symbol}')
        return

    # Normalize to base 100 at first available point
    base = rows[0]['close']
    for row in rows:
        row['symbol'] = symbol
        row['label']  = label
        row['value']  = round(row['close'] / base * 100, 4)

    if DRY_RUN:
        print(f'  [DRY] Would upsert {len(rows)} rows for {symbol}')
        return

    # Upsert in batches
    batch_size = 50
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        r = requests.post(
            f'{SUPABASE_URL}/rest/v1/benchmark_history',
            headers={**SB_HEADERS, 'Prefer': 'resolution=merge-duplicates'},
            json=batch,
            timeout=20
        )
        if r.status_code not in (200, 201):
            print(f'  [Bench ERR] {r.status_code}: {r.text[:200]}')
    print(f'  [Bench] {symbol} ({label}): {len(rows)} points upserted')

# ═══════════════════════════════════════
# MAIN
# ═══════════════════════════════════════
def main():
    now = datetime.now(timezone.utc).isoformat()
    print(f'{"="*55}')
    print(f'OVC Price Updater — {now}{"  [DRY RUN]" if DRY_RUN else ""}')
    print(f'{"="*55}')

    # 1. Fetch portfolio
    positions = sb_get('portfolio', '?select=ticker,name,current_price,currency,api_method')
    if not positions:
        print('[WARN] Portfolio is empty — nothing to update.')
        return

    print(f'[Portfolio] {len(positions)} positions')

    # 2. Sort by method
    yahoo_batch, brvm_batch, manual_skip = [], [], []
    for p in positions:
        m = (p.get('api_method') or '').lower()
        t = p.get('ticker', '')
        if m == 'manual':
            manual_skip.append(t)
        elif 'brvm' in m:
            brvm_batch.append(t)
        else:
            yahoo_batch.append(t)

    print(f'  Yahoo: {yahoo_batch or "none"}')
    print(f'  BRVM:  {brvm_batch  or "none"}')
    print(f'  Skip:  {manual_skip or "none"}')

    # 3. Fetch Yahoo prices (batches of 15)
    prices = {}
    for i in range(0, len(yahoo_batch), 15):
        chunk = yahoo_batch[i:i + 15]
        fetched = yahoo_prices(chunk)
        prices.update(fetched)
        time.sleep(0.6)

    # 4. BRVM — try Yahoo with .BV suffix
    for t in brvm_batch:
        sym = t + '.BV'
        p   = yahoo_prices([sym])
        if p.get(sym):
            prices[t] = p[sym]
            print(f'  [BRVM] {t} → {sym}: {p[sym]}')
        else:
            print(f'  [BRVM] {t}: not on Yahoo, price unchanged')

    # 5. Update Supabase
    updated = skipped = errors = 0
    for pos in positions:
        t      = pos['ticker']
        method = (pos.get('api_method') or '').lower()
        if method == 'manual':
            skipped += 1
            continue
        new_p = prices.get(t)
        if new_p is None:
            print(f'  [MISS] {t}: no price found')
            skipped += 1
            continue
        old_p = float(pos.get('current_price') or 0)
        chg   = ((new_p - old_p) / old_p * 100) if old_p else 0
        print(f'  [{"DRY" if DRY_RUN else "OK "}] {t:12s} {old_p:10.4f} → {new_p:10.4f}  ({chg:+.2f}%)')
        try:
            sb_patch('portfolio', {'current_price': new_p}, f'ticker=eq.{t}')
            updated += 1
        except Exception as exc:
            print(f'  [ERR] {t}: {exc}')
            errors += 1
        time.sleep(0.1)

    # 6. FX rates → fund_settings.fx_rates
    print('\n[FX] Fetching rates…')
    fx = fetch_fx()
    if fx:
        fx_payload = {**fx, 'XOF': 0.0015245, 'EUR': 1.0, 'updated_at': now}
        print(f'  Rates: {fx_payload}')
        try:
            sb_patch('fund_settings', {'fx_rates': json.dumps(fx_payload)}, 'id=eq.1')
            print('  [OK] FX rates stored in fund_settings.fx_rates')
        except Exception as exc:
            print(f'  [WARN] Could not store FX (column may need migration): {exc}')

    # 7. Benchmark data (S&P 500 + MSCI World proxy)
    print('\n[Benchmark] Fetching weekly history…')
    store_benchmark('^GSPC',  'S&P 500')
    store_benchmark('^STOXX50E', 'Euro Stoxx 50')
    time.sleep(1)

    # 8. Summary
    print(f'\n{"="*55}')
    print(f'Updated: {updated}  |  Skipped: {skipped}  |  Errors: {errors}')
    print(f'Finished: {datetime.now(timezone.utc).isoformat()}')
    if errors:
        sys.exit(1)

if __name__ == '__main__':
    main()
