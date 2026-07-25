// Supabase Edge Function — Google News RSS proxy (veille A&S Terminal)
// Déployer : npx supabase functions deploy news-feed --no-verify-jwt
//
// Testé en direct avant de choisir cette source : contrairement à l'endpoint
// Yahoo quoteSummary (crumb/cookies fragiles), le flux RSS Google News est
// public, sans authentification, et structuré de façon stable. Usage
// interne/personnel uniquement — le flux porte une mention de copyright
// Google restreignant à un usage de lecteur de flux personnel.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Content-Type': 'application/json',
};

function extract(pattern: RegExp, text: string): string {
  const m = text.match(pattern);
  return m ? m[1] : '';
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  try {
    const { query } = await req.json();
    if (!query) return new Response(JSON.stringify({ error: 'query requise' }), { status: 400, headers: CORS });

    const url = `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=fr&gl=FR&ceid=FR:fr`;
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    });
    if (!resp.ok) throw new Error(`Google News HTTP ${resp.status}`);
    const xml = await resp.text();

    const items = xml.match(/<item>[\s\S]*?<\/item>/g) || [];
    const results = items.slice(0, 10).map((it) => {
      const title  = extract(/<title>([\s\S]*?)<\/title>/, it);
      const link   = extract(/<link>([\s\S]*?)<\/link>/, it);
      const pub    = extract(/<pubDate>([\s\S]*?)<\/pubDate>/, it);
      const source = extract(/<source url="[^"]*">([\s\S]*?)<\/source>/, it);
      return { title, link, pubDate: pub, source };
    });

    return new Response(JSON.stringify({ query, results }), { headers: CORS });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), results: [] }), { status: 500, headers: CORS });
  }
});
