-- ══════════════════════════════════════════════════════════════
-- OVC — Attribuer "Oswald Jaûres KOFFI" à tous les articles déjà publiés
-- À exécuter dans Supabase → SQL Editor, APRÈS le correctif de récursion
-- (2026-07-25-fix-admins-recursion.sql), sinon cette requête échouera aussi.
--
-- La bio auteur ajoutée sur article.html ne s'affiche que si le champ
-- `author` vaut exactement "Oswald Jaûres KOFFI" (insensible à la casse/
-- aux accents). Cette requête met à jour tous les articles publiés d'un
-- coup, plutôt que de les rééditer un par un dans l'admin.
-- ══════════════════════════════════════════════════════════════

UPDATE articles
SET author = 'Oswald Jaûres KOFFI'
WHERE published = true;

-- Vérifier :
-- SELECT slug, title, author FROM articles WHERE published = true ORDER BY published_at DESC;
