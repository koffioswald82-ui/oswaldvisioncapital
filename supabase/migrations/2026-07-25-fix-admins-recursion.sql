-- ══════════════════════════════════════════════════════════════
-- OVC — CORRECTIF URGENT : récursion infinie sur la table admins
-- À exécuter IMMÉDIATEMENT dans Supabase → SQL Editor
--
-- BUG : la migration 2026-07-24-fix-admin-rls.sql a créé une policy sur
-- `admins` qui se référence elle-même :
--   USING (auth.uid() IN (SELECT id FROM public.admins))
-- appliquée SUR LA TABLE admins ELLE-MÊME. Postgres détecte la boucle et
-- rejette toute requête sur n'importe quelle table dont la policy vérifie
-- le statut admin (portfolio, nav_history, benchmark_history, articles,
-- transactions, subscribers, episodes, fund_snapshots, storage.objects) —
-- confirmé en direct : le site ne peut plus rien lire depuis Supabase.
--
-- CORRECTIF : remplacer la sous-requête brute par une fonction
-- SECURITY DEFINER, qui contourne la RLS en interne (pattern standard
-- Supabase pour ce cas précis) — plus aucune policy ne référence `admins`
-- directement, donc plus de récursion possible.
-- ══════════════════════════════════════════════════════════════

-- 1. Supprimer la policy self-référentielle sur admins (personne n'a besoin
--    de lire cette table directement depuis le client — seule la fonction
--    ci-dessous y accède, en interne, avec des privilèges élevés).
DROP POLICY IF EXISTS "Admins can read admins" ON public.admins;

-- 2. Fonction qui vérifie le statut admin sans jamais déclencher la RLS de
--    la table admins (SECURITY DEFINER = s'exécute avec les privilèges du
--    créateur de la fonction, qui contournent la RLS).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid());
$$;

-- 3. Remplacer auth.uid() IN (SELECT id FROM public.admins) par
--    public.is_admin() sur toutes les policies touchées par la migration
--    précédente.
DROP POLICY IF EXISTS "Admin All Access" ON fund_settings;
CREATE POLICY "Admin All Access" ON fund_settings FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admin All Access" ON portfolio;
CREATE POLICY "Admin All Access" ON portfolio FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admin All Access" ON nav_history;
CREATE POLICY "Admin All Access" ON nav_history FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admin All Access" ON transactions;
CREATE POLICY "Admin All Access" ON transactions FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admin Select" ON subscribers;
CREATE POLICY "Admin Select" ON subscribers FOR SELECT USING (public.is_admin());

DROP POLICY IF EXISTS "Admin Update View" ON subscribers;
CREATE POLICY "Admin Update View" ON subscribers FOR UPDATE USING (public.is_admin());

DROP POLICY IF EXISTS "Admin Delete" ON subscribers;
CREATE POLICY "Admin Delete" ON subscribers FOR DELETE USING (public.is_admin());

DROP POLICY IF EXISTS "Auth all articles" ON articles;
CREATE POLICY "Auth all articles" ON articles FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Auth write benchmark" ON benchmark_history;
CREATE POLICY "Auth write benchmark" ON benchmark_history FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Auth write episodes" ON episodes;
CREATE POLICY "Auth write episodes" ON episodes FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admin all snapshots" ON fund_snapshots;
CREATE POLICY "Admin all snapshots" ON fund_snapshots FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Auth upload audio" ON storage.objects;
CREATE POLICY "Auth upload audio" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'audio-files' AND public.is_admin());

DROP POLICY IF EXISTS "Auth delete audio" ON storage.objects;
CREATE POLICY "Auth delete audio" ON storage.objects
  FOR DELETE USING (bucket_id = 'audio-files' AND public.is_admin());

-- ── Vérification après exécution ──
-- SELECT * FROM public.admins;                       -- doit fonctionner (vous, via SQL Editor)
-- curl .../rest/v1/articles?select=slug&published=eq.true  -- doit renvoyer des données, plus d'erreur 42P17
