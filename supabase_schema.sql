-- 1. Table des paramètres du fonds (Cash, parts en circulation)
CREATE TABLE fund_settings (
  id integer PRIMARY KEY DEFAULT 1,
  cash numeric(15,2) NOT NULL DEFAULT 100000,
  parts numeric(15,4) NOT NULL DEFAULT 1000,
  last_update timestamp with time zone DEFAULT now()
);

-- Insérer la valeur par défaut pour la configuration globale du fonds
INSERT INTO fund_settings (id, cash, parts) VALUES (1, 100000, 1000);

ALTER TABLE fund_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin All Access" ON fund_settings FOR ALL USING (auth.role() = 'authenticated');
-- Lecture publique nécessaire pour performance.html (calcul de la NAV côté visiteur)
CREATE POLICY "Public Read" ON fund_settings FOR SELECT USING (true);

-- 2. Table du Portefeuille (Portfolio)
CREATE TABLE portfolio (
  ticker text PRIMARY KEY,
  name text NOT NULL,
  zone text NOT NULL,
  sector text,
  entry_price numeric(10,4) NOT NULL,
  current_price numeric(10,4) NOT NULL,




  
  currency text NOT NULL,
  api_method text NOT NULL,
  qty numeric(15,4) DEFAULT 0
);

ALTER TABLE portfolio ENABLE ROW LEVEL SECURITY;
-- Le dashboard public aura besoin de lire ces données (cours) s'il devient dynamique, mais pour l'instant seul l'admin modifie.
-- On laisse la lecture publique pour la page performance si besoin, sinon on restreint. Restreignons à l'admin pour l'instant.
CREATE POLICY "Admin All Access" ON portfolio FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Public Read" ON portfolio FOR SELECT USING (true); -- Utile si on veut afficher le portefeuille dynamiquement

-- 3. Historique de la VL (NAV History)
CREATE TABLE nav_history (
  id serial PRIMARY KEY,
  date date NOT NULL,
  nav numeric(10,4) NOT NULL,
  wchg numeric(10,4),
  cum numeric(10,4),
  capital numeric(15,2),
  cash numeric(15,2),
  parts numeric(15,4),
  note text,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE nav_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin All Access" ON nav_history FOR ALL USING (auth.role() = 'authenticated');
-- Lecture publique autorisée pour afficher le graphique de la VL sur le site
CREATE POLICY "Public Read" ON nav_history FOR SELECT USING (true);

-- 4. Transactions internes du fonds
CREATE TABLE transactions (
  id serial PRIMARY KEY,
  date date NOT NULL,
  type text NOT NULL,
  ticker text,
  qty numeric(15,4),
  price numeric(10,4),
  total_eur numeric(15,2),
  cash_after numeric(15,2),
  note text,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin All Access" ON transactions FOR ALL USING (auth.role() = 'authenticated');

-- 5. Souscripteurs (Subscribers via les formulaires)
CREATE TABLE subscribers (
  id serial PRIMARY KEY,
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NOT NULL,
  amount numeric(15,2) NOT NULL,
  currency text,
  parts numeric(15,4),
  nav_entry numeric(10,4),
  objective text,
  horizon text,
  risk text,
  country text,
  date timestamp with time zone DEFAULT now()
);

ALTER TABLE subscribers ENABLE ROW LEVEL SECURITY;
-- Politique CRITIQUE : Tout le monde peut insérer (afin que le formulaire public fonctionne sans connexion)
CREATE POLICY "Public Insert" ON subscribers FOR INSERT WITH CHECK (true);
-- Seul l'administrateur peut visualiser la liste des souscripteurs
CREATE POLICY "Admin Select" ON subscribers FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admin Update View" ON subscribers FOR UPDATE USING (auth.role() = 'authenticated');
CREATE POLICY "Admin Delete" ON subscribers FOR DELETE USING (auth.role() = 'authenticated');

-- 6. Articles CMS
CREATE TABLE articles (
  slug          TEXT PRIMARY KEY,
  type          TEXT NOT NULL DEFAULT 'analyse',   -- 'analyse' | 'macro'
  title         TEXT NOT NULL,
  ticker        TEXT,
  zone          TEXT,
  strategy      TEXT,
  lede          TEXT,
  reco          TEXT,                               -- BUY | HOLD | SELL | NEUTRAL
  published     BOOLEAN DEFAULT false,
  published_at  DATE,
  scheduled_at  TIMESTAMPTZ,                        -- auto-publish when this timestamp passes
  archived      BOOLEAN DEFAULT false,              -- soft-delete / retire article
  author        TEXT DEFAULT 'OVC Research',
  cover_image   TEXT,                               -- URL image de couverture (optionnel)
  tags          TEXT[] DEFAULT '{}',                -- ex: {'dividende','telecoms','afrique'}
  reading_time  INT DEFAULT 1,                      -- minutes (calculé au save)
  views         INT DEFAULT 0,                      -- compteur de vues
  series        TEXT,                               -- nom d'une série (ex: 'Afrique Q1 2026')
  series_order  INT DEFAULT 0,
  meta          JSONB DEFAULT '{}',                 -- badges, stamp
  sections      JSONB DEFAULT '[]',
  updated_at    TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
-- Lecture publique des articles publiés (non archivés)
CREATE POLICY "Public read published articles" ON articles
  FOR SELECT USING (published = true AND (archived IS NULL OR archived = false));
-- Admin a tous les droits (brouillons, archivés, écriture, suppression)
CREATE POLICY "Auth all articles" ON articles
  FOR ALL USING (auth.role() = 'authenticated');

-- Index pour accélérer les requêtes fréquentes
CREATE INDEX idx_articles_published_at ON articles (published_at DESC) WHERE published = true;
CREATE INDEX idx_articles_zone        ON articles (zone)     WHERE published = true;
CREATE INDEX idx_articles_type        ON articles (type)     WHERE published = true;
CREATE INDEX idx_articles_series      ON articles (series)   WHERE series IS NOT NULL;
CREATE INDEX idx_articles_scheduled   ON articles (scheduled_at) WHERE published = false AND scheduled_at IS NOT NULL;

-- Trigger : met à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;
CREATE TRIGGER articles_updated_at
  BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger : renseigne published_at automatiquement lors de la 1ère publication
CREATE OR REPLACE FUNCTION set_published_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.published = true AND OLD.published = false AND NEW.published_at IS NULL THEN
    NEW.published_at = CURRENT_DATE;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER articles_published_at
  BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION set_published_at();

-- ──────────────────────────────────────────────
-- PUBLICATION PLANIFIÉE — pg_cron (auto-publish)
-- Active l'extension dans Supabase :
--   Dashboard → Extensions → pg_cron → Enable
-- Puis exécute :
-- ──────────────────────────────────────────────
-- SELECT cron.schedule(
--   'ovc-auto-publish',          -- nom du job (unique)
--   '*/30 * * * *',              -- toutes les 30 minutes
--   $$
--     UPDATE articles
--     SET published = true
--     WHERE published = false
--       AND scheduled_at IS NOT NULL
--       AND scheduled_at <= now()
--       AND (archived IS NULL OR archived = false);
--   $$
-- );
-- Pour voir les jobs : SELECT * FROM cron.job;
-- Pour supprimer   : SELECT cron.unschedule('ovc-auto-publish');

-- ──────────────────────────────────────────────
-- COMPTEUR DE VUES — function RPC publique
-- Permet à article.html d'incrémenter sans auth
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION increment_article_views(article_slug TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE articles SET views = views + 1 WHERE slug = article_slug;
END; $$;
GRANT EXECUTE ON FUNCTION increment_article_views(TEXT) TO anon;

-- ══════════════════════════════════════════════════════
-- MIGRATION : tables et colonnes ajoutées après le lancement
-- Exécuter UNE SEULE FOIS dans Supabase SQL Editor
-- ══════════════════════════════════════════════════════

-- Colonne fx_rates dans fund_settings (stocke les taux EUR mis à jour par GitHub Actions)
ALTER TABLE fund_settings ADD COLUMN IF NOT EXISTS fx_rates TEXT;

-- Colonne strategy dans portfolio (ajoutée lors de la mise à jour CMS)
ALTER TABLE portfolio ADD COLUMN IF NOT EXISTS strategy TEXT;

-- Poids cible (%) de chaque position — nécessaire pour la page performance.html (visiteurs anonymes)
ALTER TABLE portfolio ADD COLUMN IF NOT EXISTS target_weight numeric(5,2) DEFAULT 0;

-- 7. Historique des benchmarks (S&P 500, Euro Stoxx 50 — mis à jour par GitHub Actions)
CREATE TABLE IF NOT EXISTS benchmark_history (
  id        SERIAL PRIMARY KEY,
  symbol    TEXT NOT NULL,          -- ex: '^GSPC'
  label     TEXT NOT NULL,          -- ex: 'S&P 500'
  date      DATE NOT NULL,
  close     NUMERIC(12,4) NOT NULL,
  value     NUMERIC(10,4) NOT NULL, -- normalisé base 100
  UNIQUE (symbol, date)
);

ALTER TABLE benchmark_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read benchmark" ON benchmark_history FOR SELECT USING (true);
CREATE POLICY "Auth write benchmark"  ON benchmark_history FOR ALL USING (auth.role() = 'authenticated');

CREATE INDEX IF NOT EXISTS idx_bench_symbol_date ON benchmark_history (symbol, date DESC);

-- ══════════════════════════════════════════════════════
-- MIGRATION : Audio podcast — Supabase Storage integration
-- Exécuter UNE SEULE FOIS dans Supabase SQL Editor
-- ══════════════════════════════════════════════════════

-- Colonnes audio sur articles (type='podcast' ou articles avec audio)
ALTER TABLE articles ADD COLUMN IF NOT EXISTS audio_fr_url    TEXT;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS audio_en_url    TEXT;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS audio_duration_sec INT DEFAULT 0;

-- Table dédiée aux épisodes podcast
CREATE TABLE IF NOT EXISTS episodes (
  id              SERIAL PRIMARY KEY,
  ep_number       INT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  title_fr        TEXT NOT NULL,
  title_en        TEXT,
  desc_fr         TEXT,
  desc_en         TEXT,
  tags            TEXT[] DEFAULT '{}',
  audio_fr_path   TEXT,  -- path in 'audio-files' bucket: fr/ep001.mp3
  audio_en_path   TEXT,  -- path in 'audio-files' bucket: en/ep001.mp3
  duration_sec    INT DEFAULT 0,
  published       BOOLEAN DEFAULT false,
  published_at    DATE,
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;
-- Métadonnées lisibles par tous (titre, description, durée)
CREATE POLICY "Public read episodes"   ON episodes FOR SELECT USING (published = true);
-- Seul l'admin peut créer/modifier les épisodes
CREATE POLICY "Auth write episodes"    ON episodes FOR ALL USING (auth.role() = 'authenticated');

-- ── Supabase Storage bucket 'audio-files' ──────────────
-- À créer manuellement dans le Dashboard :
--   Storage → New Bucket → Name: audio-files → Private (non public)
-- Ou via SQL :
-- INSERT INTO storage.buckets (id, name, public)
--   VALUES ('audio-files', 'audio-files', false)
--   ON CONFLICT DO NOTHING;

-- Politique de lecture : utilisateurs authentifiés (abonnés connectés) uniquement
CREATE POLICY "Auth read audio" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'audio-files'
    AND auth.role() = 'authenticated'
  );

-- Politique d'écriture (upload) : admin uniquement
CREATE POLICY "Auth upload audio" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'audio-files'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Auth delete audio" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'audio-files'
    AND auth.role() = 'authenticated'
  );

-- ── Exemples d'insertion d'épisodes ────────────────────
-- INSERT INTO episodes (ep_number, slug, title_fr, title_en, desc_fr, tags,
--   audio_fr_path, audio_en_path, duration_sec, published, published_at) VALUES
-- (3, 'ep003-nvidia-ia', 'NVIDIA et l''IA : peut-on encore investir ?',
--  'NVIDIA & AI: Can you still invest?',
--  'Après un run de +500% en 3 ans, NVIDIA est-elle encore une opportunité ?',
--  ARRAY['tech','equity'], 'fr/ep003.mp3', 'en/ep003.mp3', 1680, true, '2026-04-01'),
-- (2, 'ep002-brvm-2026', 'BRVM 2026 : les marchés africains que personne ne couvre',
--  'BRVM 2026: the African markets nobody covers',
--  'La Bourse Régionale des Valeurs Mobilières est l''une des places les moins analysées.',
--  ARRAY['africa','macro'], 'fr/ep002.mp3', 'en/ep002.mp3', 1320, true, '2026-03-01'),
-- (1, 'ep001-tarifs-trump', 'Tarifs Trump 2025 : opportunité ou piège pour l''Afrique ?',
--  'Trump Tariffs 2025: opportunity or trap for Africa?',
--  'La guerre commerciale US-Chine redistribue les flux de capitaux mondiaux.',
--  ARRAY['macro'], 'fr/ep001.mp3', 'en/ep001.mp3', 1080, true, '2026-02-01');

-- ══════════════════════════════════════════════════════
-- SNAPSHOTS — Sauvegardes automatiques avant modifications
-- Exécuter UNE SEULE FOIS dans Supabase SQL Editor
-- ══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS fund_snapshots (
  id              SERIAL PRIMARY KEY,
  snapshot_at     TIMESTAMPTZ DEFAULT now(),
  trigger_label   TEXT NOT NULL,          -- 'fund_params' | 'add_position' | 'remove_position' | 'publish_vl' | 'manual'
  cash            NUMERIC(15,2),
  parts           NUMERIC(15,4),
  nav_computed    NUMERIC(10,4),
  portfolio_json  JSONB DEFAULT '[]',
  nav_history_json JSONB DEFAULT '[]',
  note            TEXT DEFAULT ''
);

ALTER TABLE fund_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin all snapshots" ON fund_snapshots FOR ALL USING (auth.role() = 'authenticated');
