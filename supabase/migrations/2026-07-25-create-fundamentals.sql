-- ══════════════════════════════════════════════════════════════
-- OVC — Fondamentaux automatiques pour A&S Terminal
-- À exécuter dans Supabase → SQL Editor, après les migrations admin déjà en place.
-- ══════════════════════════════════════════════════════════════

-- 1. Liste des tickers à suivre au-delà du portefeuille réel
--    (comparables, idées à l'étude) — alimentée depuis A&S Terminal,
--    consommée par scripts/update_prices.py.
CREATE TABLE IF NOT EXISTS watchlist (
  ticker    TEXT PRIMARY KEY,
  added_at  TIMESTAMPTZ DEFAULT now(),
  added_for TEXT DEFAULT 'prospect'   -- 'prospect' | 'comparable'
);

ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;
-- Information de travail privée (ce qu'Oswald étudie) — admin uniquement.
CREATE POLICY "Admin All Access" ON watchlist FOR ALL USING (public.is_admin());

-- 2. Cache des fondamentaux récupérés via yfinance (scripts/update_prices.py)
CREATE TABLE IF NOT EXISTS fundamentals_cache (
  ticker             TEXT PRIMARY KEY,
  currency           TEXT,
  total_revenue      NUMERIC,
  free_cashflow      NUMERIC,
  total_debt         NUMERIC,
  total_cash         NUMERIC,
  shares_outstanding NUMERIC,
  trailing_pe        NUMERIC,
  ev_ebitda          NUMERIC,
  roe                NUMERIC,
  updated_at         TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE fundamentals_cache ENABLE ROW LEVEL SECURITY;
-- Données de marché factuelles (pas de secret) — lecture publique, cohérent
-- avec benchmark_history. Écriture réservée admin (le script utilise la
-- service role key, qui bypasse la RLS de toute façon).
CREATE POLICY "Public Read" ON fundamentals_cache FOR SELECT USING (true);
CREATE POLICY "Admin Write" ON fundamentals_cache FOR ALL USING (public.is_admin());

-- Vérification après exécution :
--   curl .../rest/v1/fundamentals_cache  (clé anon)   -> doit renvoyer [] ou des lignes
--   curl .../rest/v1/watchlist           (clé anon)   -> doit renvoyer une erreur de permission
