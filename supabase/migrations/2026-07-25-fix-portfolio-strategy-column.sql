-- ══════════════════════════════════════════════════════════════
-- OVC — Colonne manquante : portfolio.strategy
-- À exécuter UNE SEULE FOIS dans Supabase → SQL Editor
--
-- PROBLÈME CORRIGÉ :
-- admin-ovc-secret.html lit/écrit p.strategy sur la table `portfolio`
-- (badge stratégie growth/value/blend, modification de position) mais
-- cette colonne n'a jamais existé en base (confirmé via un dump du
-- schéma réel le 25/07/2026). Conséquence concrète : toute modification
-- d'une position existante (window.savePosition, mode édition) échoue
-- silencieusement en base — name/zone/sector/currency/strategy ne sont
-- persistés nulle part, seulement en mémoire locale côté navigateur.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE portfolio ADD COLUMN IF NOT EXISTS strategy TEXT;
