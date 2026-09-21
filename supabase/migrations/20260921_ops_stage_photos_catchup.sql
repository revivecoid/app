-- =============================================================================
-- Ops stage photos — CATCH-UP
-- Date: 2026-09-21
--
-- Why this exists
-- ---------------
-- 20260918_ops_stage_photos.sql was never applied to production. The schema
-- still lacks what it adds, which produced two separate user-facing failures:
--
--   * The floor's Repair Stages screen failed with
--       PostgrestException 42703: column job_milestones.stage_key does not exist
--   * Submitting a vehicle intake failed with
--       PostgrestException PGRST202: Could not find the function
--       public.ops_complete_intake(p_file_keys, p_job_id) in the schema cache
--       ... or with a single unnamed json/jsonb parameter
--
-- One missing migration, two symptoms: no column, and no RPC.
--
-- This migration is deliberately NOT a replay of the original file. That file
-- DROPs and recreates advance_job_status, and two LATER migrations
-- (20260919_fix_advance_job_status_role_resolution, 20260919_fix_advance_status_ownership)
-- supersede it. Replaying it would silently regress the live function, which is
-- currently the correct 3_inspected-era version that resolves the caller role
-- from profiles when the JWT carries none. advance_job_status is left untouched
-- here.
--
-- What it does instead, and nothing more:
--   1. job_milestones.stage_key  + the (job_id, stage_key) unique key the client
--      upserts against and the RPCs use as their ON CONFLICT target
--   2. job_milestone_photos.job_id (direct FK, so photo reads need no deep join)
--   3. The two ops RPCs that were never created
--   4. The missing INSERT/SELECT policies on job_milestone_photos
--
-- Item 4 matters as much as the RPCs. The RPCs are SECURITY DEFINER and bypass
-- RLS, so intake works once they exist — but every MID-REPAIR stage (disassembly,
-- welding, body_filler, painting, polishing, qc_finished) writes its milestone and
-- photos straight from the client over PostgREST. job_milestones already allows
-- partner personnel (verified by simulation), but job_milestone_photos did not:
-- a simulated partner_staff INSERT was refused with 42501. Without the policy the
-- next stage an operator opens would fail exactly like intake just did.
--
-- AMENDED after a dry run, before any user hit it:
--   * partner_booked_slots has booked_date, not slot_date. The original 20260918
--     migration inserted slot_date, which would have failed this RPC on every
--     admit from 3_booked. Corrected here; the same bug in the live
--     advance_job_status is fixed by 20260921_fix_booked_slots_column.sql.
--   * EXECUTE is revoked FROM PUBLIC, not merely FROM anon: a new function is
--     created with EXECUTE granted to PUBLIC (ACL '=X/...'), which
--     'REVOKE ... FROM anon' alone does not remove.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. job_milestones.stage_key — canonical stage identifier
--    Values: 'vehicle_intake','disassembly','welding','body_filler',
--            'painting','polishing','qc_finished','delivery'
--    Verified empty before adding the unique key (0 rows), so no conflict is
--    possible; the guard below re-checks rather than assuming.
-- ---------------------------------------------------------------------------
ALTER TABLE public.job_milestones
  ADD COLUMN IF NOT EXISTS stage_key TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.job_milestones'::regclass
       AND conname  = 'job_milestones_job_stage_unique'
  ) THEN
    -- A duplicate (job_id, stage_key) pair would make this fail. Fail loudly
    -- rather than skip, because ON CONFLICT (job_id, stage_key) in both the RPCs
    -- and the client upsert REQUIRES this key to exist.
    ALTER TABLE public.job_milestones
      ADD CONSTRAINT job_milestones_job_stage_unique UNIQUE (job_id, stage_key);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_job_milestones_stage_key
  ON public.job_milestones(job_id, stage_key);


-- ---------------------------------------------------------------------------
-- 2. job_milestone_photos.job_id — direct FK
-- ---------------------------------------------------------------------------
ALTER TABLE public.job_milestone_photos
  ADD COLUMN IF NOT EXISTS job_id UUID REFERENCES public.repair_jobs(id) ON DELETE CASCADE;

-- Backfill from the parent milestone for any pre-existing rows
UPDATE public.job_milestone_photos p
   SET job_id = m.job_id
  FROM public.job_milestones m
 WHERE p.milestone_id = m.id
   AND p.job_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_milestone_photos_job_id
  ON public.job_milestone_photos(job_id);


-- ---------------------------------------------------------------------------
-- 3a. RPC: ops_complete_intake
--     Called after the client has uploaded intake photos to Storage.
--     Atomically: upsert the vehicle_intake milestone, record the photo keys,
--     book the slot if coming from 3_booked, advance status to 5_admitted.
--     Allowed: partner_staff, partner_driver, partner_mechanic, master_admin.
--
--     The role check admits either ops role regardless of the workshop's
--     ops_view_mode. That is intentional: whoever actually takes delivery of the
--     vehicle records it. The mode governs which stages the UI offers, not
--     whether a legitimate operator may complete the one in front of them.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ops_complete_intake(UUID, TEXT[]);

CREATE FUNCTION public.ops_complete_intake(
  p_job_id    UUID,
  p_file_keys TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job         RECORD;
  v_caller_role TEXT;
  v_partner_id  UUID;
  v_milestone   RECORD;
  v_file_key    TEXT;
BEGIN
  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  IF v_caller_role NOT IN ('partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized role: ' || COALESCE(v_caller_role, 'null'));
  END IF;

  IF p_file_keys IS NULL OR array_length(p_file_keys, 1) IS NULL OR array_length(p_file_keys, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'At least one photo is required for vehicle intake.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  IF v_caller_role <> 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not assigned to your workshop.');
  END IF;

  IF v_job.status NOT IN ('3_booked', '4_paid') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Cannot admit from status: %s. Expected 3_booked or 4_paid.', v_job.status));
  END IF;

  INSERT INTO public.job_milestones (job_id, milestone_name, stage_key, status, completed_by, completed_at)
  VALUES (p_job_id, 'Vehicle Intake', 'vehicle_intake', 'completed', auth.uid(), NOW())
  ON CONFLICT (job_id, stage_key) DO UPDATE
    SET status = 'completed', completed_by = auth.uid(), completed_at = NOW()
  RETURNING * INTO v_milestone;

  FOREACH v_file_key IN ARRAY p_file_keys LOOP
    INSERT INTO public.job_milestone_photos (milestone_id, job_id, uploaded_by, file_key)
    VALUES (v_milestone.id, p_job_id, auth.uid(), v_file_key);
  END LOOP;

  IF v_job.status = '3_booked' AND v_job.scheduled_date IS NOT NULL THEN
    -- booked_date, NOT slot_date: partner_booked_slots has no slot_date column.
    -- The original 20260918 migration inserted slot_date and would have failed
    -- here every time; caught by a dry run before it reached a user.
    INSERT INTO public.partner_booked_slots (partner_id, job_id, booked_date)
    VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE public.repair_jobs
     SET status = '5_admitted', status_changed_at = NOW()
   WHERE id = p_job_id;

  RETURN jsonb_build_object(
    'success', true,
    'milestone_id', v_milestone.id,
    'photos_saved', array_length(p_file_keys, 1),
    'new_status', '5_admitted'
  );
END;
$$;

-- From PUBLIC, not merely from anon: a function is created with EXECUTE granted
-- to PUBLIC (the ACL starts with '=X/...'), and 'REVOKE ... FROM anon' does not
-- remove that, so anon would still reach it. Verified after applying.
REVOKE EXECUTE ON FUNCTION public.ops_complete_intake(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_complete_intake(UUID, TEXT[]) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3b. RPC: ops_complete_delivery
--     Same shape: record the delivery milestone + photos, advance to 9_done.
--     Allowed: partner_driver, partner_mechanic, master_admin. partner_staff is
--     excluded only because delivery was historically a valet action; under
--     all_access the UI offers it, and staff will get a clear message here
--     rather than a silent failure. Widen this list when that is decided.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ops_complete_delivery(UUID, TEXT[]);

CREATE FUNCTION public.ops_complete_delivery(
  p_job_id    UUID,
  p_file_keys TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job         RECORD;
  v_caller_role TEXT;
  v_partner_id  UUID;
  v_milestone   RECORD;
  v_file_key    TEXT;
BEGIN
  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  IF v_caller_role NOT IN ('partner_driver', 'partner_mechanic', 'master_admin') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Only drivers, mechanics or admins can complete delivery. Your role: %s', COALESCE(v_caller_role, 'null')));
  END IF;

  IF p_file_keys IS NULL OR array_length(p_file_keys, 1) IS NULL OR array_length(p_file_keys, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'At least one delivery photo is required.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  IF v_caller_role <> 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not assigned to your workshop.');
  END IF;

  IF v_job.status <> '8_awaiting_delivery' THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Cannot complete delivery from status: %s. Expected 8_awaiting_delivery.', v_job.status));
  END IF;

  INSERT INTO public.job_milestones (job_id, milestone_name, stage_key, status, completed_by, completed_at)
  VALUES (p_job_id, 'Delivery / Pickup', 'delivery', 'completed', auth.uid(), NOW())
  ON CONFLICT (job_id, stage_key) DO UPDATE
    SET status = 'completed', completed_by = auth.uid(), completed_at = NOW()
  RETURNING * INTO v_milestone;

  FOREACH v_file_key IN ARRAY p_file_keys LOOP
    INSERT INTO public.job_milestone_photos (milestone_id, job_id, uploaded_by, file_key)
    VALUES (v_milestone.id, p_job_id, auth.uid(), v_file_key);
  END LOOP;

  UPDATE public.repair_jobs
     SET status = '9_done', status_changed_at = NOW()
   WHERE id = p_job_id;

  RETURN jsonb_build_object(
    'success', true,
    'milestone_id', v_milestone.id,
    'photos_saved', array_length(p_file_keys, 1),
    'new_status', '9_done'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. job_milestone_photos policies for partner personnel.
--
--    Scoped to the caller's own workshop via get_my_partner_id() (reads
--    partner_id from the token, so no hop through profiles RLS). Mirrors how the
--    working job_milestones policies are scoped.
--
--    SELECT is included deliberately: the stages screen counts photos per
--    milestone, and with only customer/admin read policies that count silently
--    came back empty rather than erroring.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Enable INSERT for partner personnel on photos" ON public.job_milestone_photos;
CREATE POLICY "Enable INSERT for partner personnel on photos"
  ON public.job_milestone_photos FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
        FROM public.job_milestones m
        JOIN public.repair_jobs r ON r.id = m.job_id
       WHERE m.id = job_milestone_photos.milestone_id
         AND r.partner_id = get_my_partner_id()
    )
  );

DROP POLICY IF EXISTS "Enable SELECT for partner personnel on photos" ON public.job_milestone_photos;
CREATE POLICY "Enable SELECT for partner personnel on photos"
  ON public.job_milestone_photos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.job_milestones m
        JOIN public.repair_jobs r ON r.id = m.job_id
       WHERE m.id = job_milestone_photos.milestone_id
         AND r.partner_id = get_my_partner_id()
    )
  );


-- ---------------------------------------------------------------------------
-- 5. Diagnostic. The Management API returns only the LAST result set, so this
--    is the single trailing SELECT. is_master_admin()/get_my_partner_id() cannot
--    be exercised here (auth.uid() is NULL in a migration body, so they return
--    null/false by design) — the RPCs and policies are asserted separately with
--    a simulated JWT.
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'job_milestones'
      AND column_name = 'stage_key')                                   AS has_stage_key,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'job_milestone_photos'
      AND column_name = 'job_id')                                      AS photos_has_job_id,
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'public.job_milestones'::regclass
      AND conname  = 'job_milestones_job_stage_unique')                AS has_unique_key,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('ops_complete_intake', 'ops_complete_delivery')) AS ops_rpc_count,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'job_milestone_photos'
      AND policyname LIKE 'Enable % for partner personnel on photos')  AS photo_policy_count;
