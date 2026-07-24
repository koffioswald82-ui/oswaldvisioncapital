-- ══════════════════════════════════════════════════════════════
-- OVC — Correction critique des règles RLS (Row Level Security)
-- À exécuter UNE SEULE FOIS dans Supabase → SQL Editor
--
-- PROBLÈME CORRIGÉ :
-- Toutes les policies d'écriture utilisaient `auth.role() = 'authenticated'`,
-- ce qui autorise N'IMPORTE QUEL compte connecté (y compris un investisseur
-- qui s'inscrit normalement via mon-compte.html) à modifier le portefeuille,
-- la NAV, le cash, les transactions, les articles publiés, etc.
--
-- Cette migration crée une table `admins` listant explicitement les seuls
-- comptes autorisés à écrire, et remplace `auth.role() = 'authenticated'`
-- par une vérification d'appartenance à cette table sur toutes les
-- policies d'écriture existantes.
-- ══════════════════════════════════════════════════════════════

-- 1. Table des administrateurs autorisés
CREATE TABLE IF NOT EXISTS public.admins (
  id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note       text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
-- Aucune policy publique : accessible uniquement via le SQL Editor
-- (service_role) ou par vous-même une fois admin (voir policy ci-dessous).
CREATE POLICY "Admins can read admins" ON public.admins
  FOR SELECT USING (auth.uid() IN (SELECT id FROM public.admins));

-- 2. ⚠️ ÉTAPE MANUELLE OBLIGATOIRE — remplacez l'email ci-dessous par
--    votre VRAI email admin (celui que vous utilisez pour vous connecter
--    à admin-ovc-secret.html via Supabase Auth), puis exécutez cette ligne :
--
-- INSERT INTO public.admins (id, note)
--   SELECT id, 'Oswald — admin principal' FROM auth.users
--   WHERE email = 'REMPLACEZ_PAR_VOTRE_EMAIL_ADMIN@exemple.com'
-- ON CONFLICT DO NOTHING;
--
-- Vérifiez ensuite que ça a fonctionné :
-- SELECT * FROM public.admins;

-- 3. Remplacement de auth.role()='authenticated' par une vérification admin réelle
--    sur toutes les policies d'écriture existantes.

DROP POLICY IF EXISTS "Admin All Access" ON fund_settings;
CREATE POLICY "Admin All Access" ON fund_settings
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin All Access" ON portfolio;
CREATE POLICY "Admin All Access" ON portfolio
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin All Access" ON nav_history;
CREATE POLICY "Admin All Access" ON nav_history
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin All Access" ON transactions;
CREATE POLICY "Admin All Access" ON transactions
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin Select" ON subscribers;
CREATE POLICY "Admin Select" ON subscribers
  FOR SELECT USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin Update View" ON subscribers;
CREATE POLICY "Admin Update View" ON subscribers
  FOR UPDATE USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin Delete" ON subscribers;
CREATE POLICY "Admin Delete" ON subscribers
  FOR DELETE USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Auth all articles" ON articles;
CREATE POLICY "Auth all articles" ON articles
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Auth write benchmark" ON benchmark_history;
CREATE POLICY "Auth write benchmark" ON benchmark_history
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Auth write episodes" ON episodes;
CREATE POLICY "Auth write episodes" ON episodes
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

DROP POLICY IF EXISTS "Admin all snapshots" ON fund_snapshots;
CREATE POLICY "Admin all snapshots" ON fund_snapshots
  FOR ALL USING (auth.uid() IN (SELECT id FROM public.admins));

-- Storage — bucket audio-files : upload/delete réservés aux admins
-- (lecture laissée à "authenticated" = abonnés connectés, comportement voulu)
DROP POLICY IF EXISTS "Auth upload audio" ON storage.objects;
CREATE POLICY "Auth upload audio" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'audio-files' AND auth.uid() IN (SELECT id FROM public.admins)
  );

DROP POLICY IF EXISTS "Auth delete audio" ON storage.objects;
CREATE POLICY "Auth delete audio" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'audio-files' AND auth.uid() IN (SELECT id FROM public.admins)
  );

-- 4. Garde-fous sur l'insertion publique des souscripteurs (subscribe.html) :
--    empêche l'insertion de valeurs aberrantes via un appel direct à l'API
--    (contournant le formulaire) tout en laissant l'insertion publique ouverte.
ALTER TABLE subscribers
  ADD CONSTRAINT subscribers_amount_reasonable CHECK (amount > 0 AND amount <= 10000000);
ALTER TABLE subscribers
  ADD CONSTRAINT subscribers_email_format CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');

-- 5. Révoquer le compte de test committé en clair dans le dépôt public
--    (supabase/create-test-investor.sql — identifiants visibles par quiconque
--    lit le dépôt GitHub). À exécuter maintenant que la RLS ci-dessus limite
--    déjà les dégâts, mais le compte doit être supprimé ou son mot de passe changé :
--
-- DELETE FROM auth.users WHERE email = 'investisseur@ovc.test';
-- (ou, pour le garder comme compte de démo : changez son mot de passe
--  depuis le Dashboard Supabase → Authentication → Users)
