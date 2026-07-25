-- ══════════════════════════════════════════════════════════════
-- OVC — Table dcf_analyses pour la plateforme interne "Angele & Sinead"
-- À exécuter dans Supabase → SQL Editor, APRÈS 2026-07-25-fix-admins-recursion.sql
-- (dépend de public.is_admin(), créée par cette migration précédente).
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS dcf_analyses (
  id                 SERIAL PRIMARY KEY,
  ticker             TEXT NOT NULL,
  mode               TEXT NOT NULL DEFAULT 'fcf',   -- 'fcf' | 'dividend'
  inputs_base        JSONB NOT NULL DEFAULT '{}',
  inputs_bull        JSONB NOT NULL DEFAULT '{}',
  inputs_bear        JSONB NOT NULL DEFAULT '{}',
  results            JSONB NOT NULL DEFAULT '{}',   -- EV/equity value/valeur par action/upside par scénario
  sensitivity_matrix JSONB NOT NULL DEFAULT '[]',   -- grille WACC x g_terminal
  conviction         JSONB NOT NULL DEFAULT '{}',   -- critères pondérés + score total + reco suggérée
  notes              TEXT DEFAULT '',
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dcf_analyses_ticker ON dcf_analyses (ticker, updated_at DESC);

ALTER TABLE dcf_analyses ENABLE ROW LEVEL SECURITY;

-- Poste de travail privé — aucune lecture publique, admin uniquement,
-- via public.is_admin() (jamais de sous-requête directe sur public.admins,
-- c'est ce qui a causé la récursion corrigée dans la migration précédente).
CREATE POLICY "Admin All Access" ON dcf_analyses FOR ALL USING (public.is_admin());
