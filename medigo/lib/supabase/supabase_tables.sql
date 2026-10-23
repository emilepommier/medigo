-- Ensure required extensions exist for UUIDs and trigram indexes
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Users table (linked to Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT,
  role TEXT NOT NULL DEFAULT 'user',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index for faster email lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

-- BDPM DRUGS SCHEMA (PUBLIC, READ-ONLY)
-- =============================================================================

-- Table: drugs (CIS level: "CIS_bdpm.txt")
CREATE TABLE IF NOT EXISTS public.drugs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cis BIGINT NOT NULL UNIQUE,
  denomination TEXT NOT NULL,
  forme TEXT,
  voies TEXT[], -- valeurs séparées par ';'
  statut_amm TEXT,
  etat_commercialisation TEXT,
  date_amm DATE,
  statut_bdm TEXT, -- "Alerte" | "Warning disponibilité" | NULL
  numero_autorisation_europeenne TEXT,
  titulaires TEXT[], -- valeurs séparées par ';'
  surveillance_renforcee BOOLEAN, -- Oui/Non -> true/false
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_drugs_denomination ON public.drugs (denomination);
CREATE INDEX IF NOT EXISTS idx_drugs_forme ON public.drugs (forme);

-- Table: presentations (CIP level: "CIS_CIP_bdpm.txt")
CREATE TABLE IF NOT EXISTS public.presentations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cip13 TEXT NOT NULL UNIQUE,
  cis BIGINT NOT NULL REFERENCES public.drugs(cis) ON DELETE CASCADE,
  cip7 TEXT,
  libelle TEXT,
  statut_admin TEXT,
  etat_commercialisation TEXT,
  taux_remboursement TEXT[], -- valeurs séparées par ';'
  prix_euro NUMERIC(10,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_presentations_cis ON public.presentations (cis);
CREATE INDEX IF NOT EXISTS idx_presentations_cip7 ON public.presentations (cip7);

-- Metadata table to track import runs
CREATE TABLE IF NOT EXISTS public.drug_metadata (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  last_imported_at TIMESTAMPTZ,
  source TEXT DEFAULT 'BDPM',
  count_drugs INTEGER,
  count_presentations INTEGER
);

-- =============================================================================
-- Families, members, invites and shared pharmacy items
-- =============================================================================

-- Families table
CREATE TABLE IF NOT EXISTS public.families (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_families_created_by ON public.families(created_by);

-- Family members
CREATE TABLE IF NOT EXISTS public.family_members (
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (family_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_family_members_user ON public.family_members(user_id);

-- Family invitation codes
CREATE TABLE IF NOT EXISTS public.family_invites (
  code TEXT PRIMARY KEY,
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  used_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_family_invites_family ON public.family_invites(family_id);

-- Shared pharmacy items, unique by (family_id, cip13)
CREATE TABLE IF NOT EXISTS public.pharmacy_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  cip13 TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(family_id, cip13)
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_items_family ON public.pharmacy_items(family_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_items_cip13 ON public.pharmacy_items(cip13);

-- Per-box entries with expiry dates (source of truth)
CREATE TABLE IF NOT EXISTS public.pharmacy_item_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  cip13 TEXT NOT NULL,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at DATE NULL,
  photo_url TEXT NULL
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_item_entries_family_cip ON public.pharmacy_item_entries(family_id, cip13);
CREATE INDEX IF NOT EXISTS idx_pharmacy_item_entries_expires ON public.pharmacy_item_entries(expires_at);

-- Read-only aggregate view computed from entries (do not write to pharmacy_items anymore)
-- Mark as SECURITY INVOKER so PostgREST treats it as securable (no "unrestricted" warnings)
CREATE OR REPLACE VIEW public.pharmacy_items_view
WITH (security_invoker = on)
AS
SELECT
  e.family_id,
  e.cip13,
  COUNT(*)::INT AS quantity,
  MIN(e.expires_at) AS earliest_expires_at,
  MAX(e.added_at) AS updated_at
FROM public.pharmacy_item_entries e
GROUP BY e.family_id, e.cip13;

-- Ensure existing deployments also have security_invoker set
ALTER VIEW public.pharmacy_items_view SET (security_invoker = on);

-- =============================================================================
-- Custom (manual) items metadata
-- =============================================================================

-- Manual items that are not part of BDPM (no official CIP)
-- We reuse pharmacy_item_entries by storing a synthetic key in cip13 like 'custom:<uuid>'
-- This table stores the human-readable metadata for those synthetic keys per family.
CREATE TABLE IF NOT EXISTS public.custom_items (
  custom_key TEXT PRIMARY KEY DEFAULT ('custom:' || gen_random_uuid()),
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  laboratory TEXT NULL,
  forme TEXT NULL,
  photo_url TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (family_id, custom_key)
);
CREATE INDEX IF NOT EXISTS idx_custom_items_family ON public.custom_items(family_id);

-- Signup invites (gated registrations)
CREATE TABLE IF NOT EXISTS public.signup_invites (
  code TEXT PRIMARY KEY,
  email TEXT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  used_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_signup_invites_email ON public.signup_invites(email);
