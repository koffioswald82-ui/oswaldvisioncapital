-- ══════════════════════════════════════════════════════════════
-- OVC — Activation de la publication planifiée (pg_cron) + teaser public
-- À exécuter UNE SEULE FOIS dans Supabase → SQL Editor
--
-- Le flux de planification côté admin (admin-ovc-secret.html, panneau
-- "Planifier") existe déjà et enregistre correctement `scheduled_at` sur
-- l'article en brouillon. Ce qui manquait : (1) rien ne bascule l'article
-- en `published=true` une fois la date atteinte, (2) rien n'annonce
-- publiquement un article planifié avant sa publication.
-- ══════════════════════════════════════════════════════════════

-- 1. Extension pg_cron — si la commande échoue, activez-la d'abord via
--    Dashboard → Database → Extensions → pg_cron → Enable, puis relancez.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Job : toutes les 30 minutes, publie les articles dont l'heure planifiée
--    est passée. (Déjà documenté en commentaire dans supabase_schema.sql —
--    copié ici pour n'avoir qu'un seul endroit à exécuter.)
SELECT cron.schedule(
  'ovc-auto-publish',
  '*/30 * * * *',
  $$
    UPDATE articles
    SET published = true
    WHERE published = false
      AND scheduled_at IS NOT NULL
      AND scheduled_at <= now()
      AND (archived IS NULL OR archived = false);
  $$
);
-- Vérifier : SELECT * FROM cron.job;
-- Supprimer si besoin : SELECT cron.unschedule('ovc-auto-publish');

-- 3. Vue restreinte pour annoncer publiquement les articles planifiés à
--    venir, SANS exposer leur contenu final (sections/meta) ni élargir la
--    RLS de la table articles elle-même — seules ces colonnes sont lisibles
--    via cette vue, et seulement pour les lignes encore planifiées.
CREATE VIEW public_article_teasers AS
SELECT slug, type, title, ticker, zone, strategy, lede, author, tags, scheduled_at
FROM articles
WHERE published = false
  AND scheduled_at IS NOT NULL
  AND scheduled_at > now()
  AND (archived IS NULL OR archived = false);

GRANT SELECT ON public_article_teasers TO anon, authenticated;

-- Vérifier après exécution (clé anon, doit renvoyer [] ou des lignes, jamais
-- une erreur de permission) :
--   curl 'https://bnmjhmijhgxpjbrtwbdv.supabase.co/rest/v1/public_article_teasers' \
--     -H 'apikey: VOTRE_CLE_ANON' -H 'Authorization: Bearer VOTRE_CLE_ANON'
