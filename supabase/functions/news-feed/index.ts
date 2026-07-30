// Supabase Edge Function — Google News RSS proxy (veille A&S Terminal)
//
// ⚠️ NON UTILISÉE PAR LE SITE — testée en direct après déploiement, Google
// renvoie une erreur 503 depuis les serveurs Supabase (IP bloquée par
// l'anti-bot de Google), alors que le même flux fonctionne normalement
// depuis les serveurs GitHub Actions déjà utilisés pour les cours. A&S
// Terminal lit désormais la table `news_cache`, alimentée par
// scripts/update_prices.py (fonction fetch_news/store_news), pas cette
// fonction. Laissée déployée pour référence/débogage futur — ne pas la
// rebrancher sans retester la disponibilité depuis Supabase au préalable.
//
// Déployer : npx supabase functions deploy news-feed --no-verify-jwt
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
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
        'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
        'Referer': 'https://news.google.com/',
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
