-- Idempotent migration to simplify invite system and family sharing
-- Safe to run multiple times.

-- Required extensions
create extension if not exists pgcrypto;       -- gen_random_uuid(), gen_random_bytes
create extension if not exists pg_trgm;        -- trigram indexes (kept for search elsewhere)

-- Users table role column for admin gating (if your project uses public.users mirror)
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users' and column_name = 'role'
  ) then
    alter table if exists public.users add column role text not null default 'user';
  end if;
end $$;

-- Families: single invite code per family
create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  invite_code text
);

-- Ensure invite_code exists and is unique
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'families' and column_name = 'invite_code'
  ) then
    alter table public.families add column invite_code text;
  end if;
  -- backfill codes for existing rows
  update public.families
    set invite_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
  where invite_code is null;
  -- unique index for fast lookup
  create unique index if not exists families_invite_code_key on public.families (invite_code);
end $$;

-- Family members: a user can be in only one family
create table if not exists public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

-- Enforce unique membership per user (not IF NOT EXISTS supported directly)
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'family_members_user_unique'
  ) then
    alter table public.family_members add constraint family_members_user_unique unique (user_id);
  end if;
end $$;

-- Optional: deprecate old family_invites table by enforcing single-row semantics
create table if not exists public.family_invites (
  code text primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  used_by uuid null references auth.users(id) on delete set null,
  used_at timestamptz null
);

-- Ensure a family has only one invite row
-- 1) Deduplicate existing data to avoid unique index failures
with ranked as (
  select code, family_id, created_at,
         row_number() over (partition by family_id order by created_at desc, code desc) as rn
  from public.family_invites
)
delete from public.family_invites i
using ranked r
where i.code = r.code and i.family_id = r.family_id and r.rn > 1;

-- 2) Add the unique constraint (idempotent)
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'family_invites_one_per_family'
  ) then
    alter table public.family_invites add constraint family_invites_one_per_family unique (family_id);
  end if;
end $$;

-- Backfill: for any family without a matching row, create one matching the invite_code
insert into public.family_invites (code, family_id, created_by)
select f.invite_code, f.id, f.created_by
from public.families f
left join public.family_invites i on i.family_id = f.id
where i.family_id is null
on conflict do nothing;

-- Signup invites for account creation (admin generated)
create table if not exists public.signup_invites (
  code text primary key,
  email text null,
  role text not null default 'user',
  created_by uuid not null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_by uuid null references auth.users(id) on delete set null,
  used_at timestamptz null
);

-- RLS ---------------------------------------------------------------------------------
alter table if exists public.families enable row level security;
alter table if exists public.family_members enable row level security;
alter table if exists public.family_invites enable row level security;
alter table if exists public.signup_invites enable row level security;

-- Helper functions to avoid recursive RLS checks --------------------------------
-- SECURITY DEFINER helpers return booleans without triggering cross-table RLS recursion
create or replace function public.fn_is_family_owner(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $fn$
  select exists (
    select 1 from public.families f
    where f.id = p_family_id and f.created_by = auth.uid()
  );
$fn$;

create or replace function public.fn_is_family_member(p_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $fn$
  select exists (
    select 1 from public.family_members m
    where m.family_id = p_family_id and m.user_id = auth.uid()
  );
$fn$;

-- Families policies
do $$ begin
  -- Read own family (creator or member)
  if exists (select 1 from pg_policies where schemaname='public' and tablename='families' and policyname='families_members_read') then
    drop policy families_members_read on public.families;
  end if;
  create policy families_members_read on public.families
    for select to authenticated
    using (
      created_by = auth.uid() or public.fn_is_family_member(families.id)
    );

  -- Read by invite code (to allow joining) – exposes only code/name/id
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='families' and policyname='families_read_by_code') then
    create policy families_read_by_code on public.families
      for select to authenticated
      using (true);
  end if;

  -- Create family (self-owned)
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='families' and policyname='families_self_create') then
    create policy families_self_create on public.families
      for insert to authenticated
      with check (created_by = auth.uid());
  end if;

  -- Update only by creator
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='families' and policyname='families_creator_update') then
    create policy families_creator_update on public.families
      for update to authenticated
      using (created_by = auth.uid()) with check (created_by = auth.uid());
  end if;

  -- Delete only by creator
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='families' and policyname='families_creator_delete') then
    create policy families_creator_delete on public.families
      for delete to authenticated
      using (created_by = auth.uid());
  end if;
end $$;

-- Family members policies
do $$ begin
  -- Drop legacy recursive policy if present to avoid 42P17 (infinite recursion)
  if exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='family_members' and policyname='members_read_same_family'
  ) then
    drop policy members_read_same_family on public.family_members;
  end if;

  -- Allow users to read only their own membership rows (non-recursive)
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='family_members' and policyname='members_read_self'
  ) then
    create policy members_read_self on public.family_members
      for select to authenticated
      using (user_id = auth.uid());
  end if;

  -- Allow family creator to read all members in their family (no recursion via helper)
  if exists (
    select 1 from pg_policies where schemaname='public' and tablename='family_members' and policyname='members_read_owner'
  ) then
    drop policy members_read_owner on public.family_members;
  end if;
  create policy members_read_owner on public.family_members
    for select to authenticated
    using (
      public.fn_is_family_owner(family_members.family_id)
    );

  -- Join family (insert self only)
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='family_members' and policyname='members_insert_self') then
    create policy members_insert_self on public.family_members
      for insert to authenticated
      with check (user_id = auth.uid());
  end if;

  -- Allow family owner to update membership (e.g., role changes)
  if exists (select 1 from pg_policies where schemaname='public' and tablename='family_members' and policyname='members_owner_update') then
    drop policy members_owner_update on public.family_members;
  end if;
  create policy members_owner_update on public.family_members
    for update to authenticated
    using (public.fn_is_family_owner(family_members.family_id)) with check (true);

  -- Allow leaving a family (delete own membership)
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='family_members' and policyname='members_delete_self') then
    create policy members_delete_self on public.family_members
      for delete to authenticated
      using (user_id = auth.uid());
  end if;
end $$;

-- Family invites policies (single per family). Allow reading by anyone authenticated (join flow)
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='family_invites' and policyname='family_invites_read_all_auth') then
    create policy family_invites_read_all_auth on public.family_invites
      for select to authenticated using (true);
  end if;
  -- Only family creator can create/modify to avoid cross-table recursion
  if exists (select 1 from pg_policies where schemaname='public' and tablename='family_invites' and policyname='family_invites_manage_by_members') then
    drop policy family_invites_manage_by_members on public.family_invites;
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='family_invites' and policyname='family_invites_manage_by_owner') then
    create policy family_invites_manage_by_owner on public.family_invites
      for all to authenticated
      using (public.fn_is_family_owner(family_invites.family_id))
      with check (public.fn_is_family_owner(family_invites.family_id));
  end if;
end $$;

-- Signup invites RLS: anyone can validate; only admins can create
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='signup_invites' and policyname='signup_invites_select_all') then
    create policy signup_invites_select_all on public.signup_invites
      for select to anon, authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='signup_invites' and policyname='signup_invites_admin_insert') then
    create policy signup_invites_admin_insert on public.signup_invites
      for insert to authenticated
      with check (
        auth.uid() = '8e3f313f-0c85-4427-bcd5-a8328c2eb6a8'::uuid
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='signup_invites' and policyname='signup_invites_mark_used') then
    create policy signup_invites_mark_used on public.signup_invites
      for update to authenticated
      using (true) with check (true);
  end if;
end $$;

-- RPCs to ensure robust membership flows ---------------------------------------
-- Heal broken or duplicate membership rows for the current user
create or replace function public.rpc_heal_family_state()
returns table(family_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- remove memberships pointing to non-existent families
  delete from public.family_members m
  where m.user_id = v_uid
    and not exists (select 1 from public.families f where f.id = m.family_id);

  -- ensure only one membership per user (keep the most recent)
  with ranked as (
    select family_id, user_id, created_at,
           row_number() over (partition by user_id order by created_at desc, family_id desc) as rn
    from public.family_members where user_id = v_uid
  )
  delete from public.family_members m
  using ranked r
  where m.user_id = v_uid and m.family_id = r.family_id and r.rn > 1;

  -- return current membership (if any)
  return query
  select m.family_id from public.family_members m where m.user_id = v_uid limit 1;
end;
$$;

-- Join a family by invite code (idempotent upsert)
create or replace function public.rpc_join_family(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(p_code));
  v_family_id uuid;
begin
  select id into v_family_id from public.families where invite_code = v_code limit 1;
  if v_family_id is null then
    raise exception 'invalid_code';
  end if;

  -- repair first
  perform public.rpc_heal_family_state();

  -- upsert membership to enforce single family per user
  insert into public.family_members(family_id, user_id, role)
  values (v_family_id, v_uid, 'member')
  on conflict (user_id) do update set family_id = excluded.family_id, created_at = now();

  return v_family_id;
end;
$$;

-- End of migration
