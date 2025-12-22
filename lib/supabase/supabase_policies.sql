ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.drugs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.presentations ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.drug_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.family_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.pharmacy_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.signup_invites ENABLE ROW LEVEL SECURITY;

-- Users table policies (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_select_own'
  ) THEN
    CREATE POLICY users_select_own ON public.users FOR SELECT USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_insert_any'
  ) THEN
    CREATE POLICY users_insert_any ON public.users FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_update_any'
  ) THEN
    CREATE POLICY users_update_any ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='users_delete_own'
  ) THEN
    CREATE POLICY users_delete_own ON public.users FOR DELETE USING (auth.uid() = id);
  END IF;
END $$;

-- Domain policies (idempotent)
DO $$ BEGIN
  -- Drugs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='drugs' AND policyname='authenticated_all_drugs'
  ) THEN
    CREATE POLICY authenticated_all_drugs ON public.drugs FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
  END IF;

  -- Presentations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='presentations' AND policyname='authenticated_all_presentations'
  ) THEN
    CREATE POLICY authenticated_all_presentations ON public.presentations FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
  END IF;

  -- Drug metadata
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='drug_metadata' AND policyname='authenticated_all_drug_metadata'
  ) THEN
    CREATE POLICY authenticated_all_drug_metadata ON public.drug_metadata FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
  END IF;
END $$;

-- Families and Pharmacy (stricter policies)
DO $$ BEGIN
  -- families
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='families' AND policyname='families_select_member') THEN
    CREATE POLICY families_select_member ON public.families FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.family_members m WHERE m.family_id = id AND m.user_id = auth.uid()
      ));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='families' AND policyname='families_select_owner') THEN
    CREATE POLICY families_select_owner ON public.families FOR SELECT USING (created_by = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='families' AND policyname='families_insert_owner') THEN
    CREATE POLICY families_insert_owner ON public.families FOR INSERT WITH CHECK (created_by = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='families' AND policyname='families_update_owner') THEN
    CREATE POLICY families_update_owner ON public.families FOR UPDATE USING (created_by = auth.uid()) WITH CHECK (created_by = auth.uid());
  END IF;

  -- family_members
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_members' AND policyname='family_members_select_self') THEN
    CREATE POLICY family_members_select_self ON public.family_members FOR SELECT USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_members' AND policyname='family_members_insert_self') THEN
    CREATE POLICY family_members_insert_self ON public.family_members FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_members' AND policyname='family_members_owner_update') THEN
    CREATE POLICY family_members_owner_update ON public.family_members FOR UPDATE USING (EXISTS (
      SELECT 1 FROM public.families f WHERE f.id = family_id AND f.created_by = auth.uid()
    )) WITH CHECK (TRUE);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_members' AND policyname='family_members_owner_delete') THEN
    CREATE POLICY family_members_owner_delete ON public.family_members FOR DELETE USING (EXISTS (
      SELECT 1 FROM public.families f WHERE f.id = family_id AND f.created_by = auth.uid()
    ));
  END IF;

  -- family_invites
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_invites' AND policyname='family_invites_select_member') THEN
    CREATE POLICY family_invites_select_member ON public.family_invites FOR SELECT USING (EXISTS (
      SELECT 1 FROM public.family_members m WHERE m.family_id = family_id AND m.user_id = auth.uid()
    ) OR created_by = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_invites' AND policyname='family_invites_insert_member') THEN
    CREATE POLICY family_invites_insert_member ON public.family_invites FOR INSERT WITH CHECK (EXISTS (
      SELECT 1 FROM public.family_members m WHERE m.family_id = family_id AND m.user_id = auth.uid()
    ) AND created_by = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='family_invites' AND policyname='family_invites_update_used') THEN
    CREATE POLICY family_invites_update_used ON public.family_invites FOR UPDATE USING (true) WITH CHECK (true);
  END IF;

  -- pharmacy_items
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pharmacy_items' AND policyname='pharmacy_items_member_all') THEN
    CREATE POLICY pharmacy_items_member_all ON public.pharmacy_items FOR ALL USING (EXISTS (
      SELECT 1 FROM public.family_members m WHERE m.family_id = family_id AND m.user_id = auth.uid()
    )) WITH CHECK (EXISTS (
      SELECT 1 FROM public.family_members m WHERE m.family_id = family_id AND m.user_id = auth.uid()
    ));
  END IF;

  -- signup_invites
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='signup_invites' AND policyname='signup_invites_admin_all') THEN
    CREATE POLICY signup_invites_admin_all ON public.signup_invites FOR ALL USING (
      auth.uid() IN ('8e3f313f-0c85-4427-bcd5-a8328c2eb6a8'::uuid) OR EXISTS (
        SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'
      )
    ) WITH CHECK (
      auth.uid() IN ('8e3f313f-0c85-4427-bcd5-a8328c2eb6a8'::uuid) OR EXISTS (
        SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='signup_invites' AND policyname='signup_invites_validate_anon') THEN
    CREATE POLICY signup_invites_validate_anon ON public.signup_invites FOR SELECT USING (used_by IS NULL AND expires_at > NOW());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='signup_invites' AND policyname='signup_invites_mark_used') THEN
    CREATE POLICY signup_invites_mark_used ON public.signup_invites FOR UPDATE USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
  END IF;
END $$;
