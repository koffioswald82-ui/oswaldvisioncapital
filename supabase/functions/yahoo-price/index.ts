// Supabase Edge Function — Yahoo Finance proxy
// Déployer : npx supabase functions deploy yahoo-price --no-verify-jwt
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Content-Type': 'application/json',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  try {
    const { ticker } = await req.json();
    if (!ticker) return new Response(JSON.stringify({ error: 'ticker requis' }), { status: 400, headers: CORS });

    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?interval=1d&range=1d`;
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });

    if (!resp.ok) throw new Error(`Yahoo HTTP ${resp.status}`);
    const data = await resp.json();
    const result = data?.chart?.result?.[0];
    if (!result) throw new Error('Pas de données pour ' + ticker);

    const price     = result.meta.regularMarketPrice;
    const currency  = result.meta.currency;
    const ts        = result.meta.regularMarketTime;
    const exchange  = result.meta.exchangeName;

    return new Response(
      JSON.stringify({ ticker, price, currency, ts, exchange }),
      { headers: CORS }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: CORS }
    );
  }
});
