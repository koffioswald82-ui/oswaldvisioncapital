-- ══════════════════════════════════════════════════════════════
-- OVC — Cache de veille (actualités), alimenté par scripts/update_prices.py
-- À exécuter dans Supabase → SQL Editor.
--
-- Remplace l'appel direct à l'Edge Function news-feed : testé en direct,
-- Google News renvoie une erreur 503 depuis les serveurs Supabase
-- (IP bloquée par l'anti-bot de Google), alors que le même flux
-- fonctionne normalement depuis les serveurs GitHub Actions déjà utilisés
-- pour les cours/fondamentaux. Même schéma de contournement que pour
-- fundamentals_cache : un cache alimenté par le script Python existant,
-- plutôt qu'un appel direct fragile.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS news_cache (
  query      TEXT PRIMARY KEY,     -- requête normalisée (nom d'entreprise ou ticker)
  results    JSONB NOT NULL DEFAULT '[]',  -- [{title, link, pubDate, source}, ...]
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE news_cache ENABLE ROW LEVEL SECURITY;
-- Titres d'actualités publiques (pas de secret) — lecture publique, cohérent
-- avec fundamentals_cache/benchmark_history. Écriture admin/service key.
CREATE POLICY "Public Read" ON news_cache FOR SELECT USING (true);
CREATE POLICY "Admin Write" ON news_cache FOR ALL USING (public.is_admin());
