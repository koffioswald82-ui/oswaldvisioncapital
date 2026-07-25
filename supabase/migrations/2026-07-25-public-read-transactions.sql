-- ══════════════════════════════════════════════════════════════
-- OVC — Lecture publique du journal de décisions (transactions)
-- À exécuter UNE SEULE FOIS dans Supabase → SQL Editor
--
-- ⚠️ AVANT D'EXÉCUTER : relisez les lignes existantes de la table
-- `transactions` (Supabase → Table Editor → transactions) pour vérifier
-- qu'aucun champ `note` ne contient une information que vous ne voulez pas
-- rendre publique. Cette migration ouvre la LECTURE seule (l'écriture reste
-- réservée aux admins via public.admins, migration 2026-07-24).
-- ══════════════════════════════════════════════════════════════

CREATE POLICY "Public Read" ON transactions FOR SELECT USING (true);
