-- 1. Table des paramètres du fonds (Cash, parts en circulation)
CREATE TABLE fund_settings (
  id integer PRIMARY KEY DEFAULT 1,
  cash numeric(15,2) NOT NULL DEFAULT 100000,
  parts numeric(15,4) NOT NULL DEFAULT 1000,
  last_update timestamp with time zone DEFAULT now()
);

-- Insérer la valeur par défaut pour la configuration globale du fonds
INSERT INTO fund_settings (id, cash, parts) VALUES (1, 100000, 1000);

-- Autoriser uniquement les administrateurs connectés
ALTER TABLE fund_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin All Access" ON fund_settings FOR ALL USING (auth.role() = 'authenticated');

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
  slug TEXT PRIMARY KEY,
  type TEXT NOT NULL DEFAULT 'analyse',
  title TEXT NOT NULL,
  ticker TEXT,
  zone TEXT,
  strategy TEXT,
  lede TEXT,
  reco TEXT,
  published BOOLEAN DEFAULT false,
  published_at DATE,
  meta JSONB DEFAULT '{}',
  sections JSONB DEFAULT '[]',
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
-- Lecture publique des articles publiés
CREATE POLICY "Public read published articles" ON articles FOR SELECT USING (published = true);
-- Admin a tous les droits (lecture brouillons inclus, écriture, suppression)
CREATE POLICY "Auth all articles" ON articles FOR ALL USING (auth.role() = 'authenticated');
