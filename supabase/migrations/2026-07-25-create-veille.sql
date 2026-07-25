-- ══════════════════════════════════════════════════════════════
-- OVC — Carnet de veille manuel pour A&S Terminal
-- À exécuter dans Supabase → SQL Editor.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS veille_notes (
  id         SERIAL PRIMARY KEY,
  ticker     TEXT,                     -- nullable : une note peut être générale/macro
  title      TEXT NOT NULL,
  url        TEXT,
  note       TEXT DEFAULT '',
  tags       TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_veille_notes_ticker ON veille_notes (ticker, created_at DESC);

ALTER TABLE veille_notes ENABLE ROW LEVEL SECURITY;
-- Carnet de travail privé — admin uniquement (même pattern que dcf_analyses/watchlist).
CREATE POLICY "Admin All Access" ON veille_notes FOR ALL USING (public.is_admin());
