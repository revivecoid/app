-- =============================================================================
-- Migration: Fix partner data access — jobs visible + photos insertable
-- Date: 2026-09-18
-- Problems fixed:
--   1. Partner dashboard shows empty: profiles RLS blocks the JOIN on customer
--      profiles when fetching repair_jobs (partner can only read own row).
--   2. repair_photos INSERT blocked for partner_staff and partner_driver.
--   3. ops_floor_screen: same profiles JOIN issue for staff reading jobs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. profiles SELECT: partners can read customer profiles for their jobs.
--    Scope is tight: only profiles that are the customer_id of a repair_job
--    assigned to the caller's workshop. No fishing for unrelated users.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Partners can read customer profiles for their jobs" ON public.profiles;

CREATE POLICY "Partners can read customer profiles for their jobs"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (
    -- The profile being read is a customer of a job assigned to this partner
    EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.customer_id = profiles.id
        AND rj.partner_id = public.get_my_partner_id()
    )
    -- Caller must actually be a partner role (defence in depth)
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN (
      'partner_mechanic', 'partner_staff', 'partner_driver'
    )
  );


-- ---------------------------------------------------------------------------
-- 2. repair_photos INSERT: partner_staff and partner_driver can insert
--    photo records for jobs assigned to their workshop.
--    (partner_mechanic INSERT already exists via phase1 migration.)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Ops staff can insert repair photos" ON public.repair_photos;

CREATE POLICY "Ops staff can insert repair photos"
  ON public.repair_photos
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.jwt() -> 'app_metadata' ->> 'role') IN ('partner_staff', 'partner_driver')
    AND EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = repair_photos.job_id
        AND rj.partner_id = public.get_my_partner_id()
    )
  );

-- repair_photos SELECT: ops staff can read photos for their workshop's jobs
DROP POLICY IF EXISTS "Ops staff can read repair photos" ON public.repair_photos;

CREATE POLICY "Ops staff can read repair photos"
  ON public.repair_photos
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') IN ('partner_staff', 'partner_driver')
    AND EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = repair_photos.job_id
        AND rj.partner_id = public.get_my_partner_id()
    )
  );


-- ---------------------------------------------------------------------------
-- 3. repair_jobs SELECT: extend existing partner policy to also cover
--    partner_staff and partner_driver (currently only partner_mechanic via
--    get_my_partner_id() which works for all roles, but be explicit).
--    The existing "Enable SELECT for partner personnel on repair_jobs" from
--    20260910_fix_repair_jobs_rls.sql covers staff/driver already via
--    get_my_partner_id(). Verify it's present; if not, recreate it.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'repair_jobs'
      AND policyname = 'Enable SELECT for partner personnel on repair_jobs'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "Enable SELECT for partner personnel on repair_jobs"
        ON public.repair_jobs
        FOR SELECT
        USING (
          partner_id = COALESCE(
            auth.jwt() -> 'app_metadata' ->> 'partner_id',
            auth.jwt() -> 'user_metadata' ->> 'partner_id'
          )::uuid
        )
    $pol$;
  END IF;
END $$;
