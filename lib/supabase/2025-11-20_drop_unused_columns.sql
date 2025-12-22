-- Supprimer les colonnes non utilisées dans public.presentations
-- A exécuter dans le SQL Editor de Supabase (ou via migrations CLI)

begin;

-- Colonnes jugées non nécessaires pour l'app actuelle
alter table if exists public.presentations
  drop column if exists date_declaration,
  drop column if exists agrement_collectivites,
  drop column if exists indications_remboursement;

-- Optionnel: nettoyer d'éventuels index hérités (si vous en aviez créés)
drop index if exists presentations_date_declaration_idx;
drop index if exists presentations_agrement_collectivites_idx;
drop index if exists presentations_indications_remboursement_idx;

commit;
