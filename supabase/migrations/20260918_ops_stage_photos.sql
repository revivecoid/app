-- =============================================================================
-- Migration: Ops Stage Photos — per-milestone photo evidence + role transitions
-- Date: 2026-09-18
-- Scope:
--   1. Add `stage_key` to job_milestones for canonical stage identification
--   2. Add `job_id` direct FK to job_milestone_photos (avoids deep JOIN for RLS)
--   3. Extend advance_job_status: partner_staff can admit (5) and progress (6→7)
--              partner_driver can deliver (8→9) — pickup (4→5) handled via intake RPC
--   4. New RPC: ops_complete_intake — atomic photo upload record + 5_admitted advance
--              for driver pickup flow (called after Supabase Storage upload completes)
--   5. New RPC: ops_complete_delivery — atomic photo record + 9_done advance
--   6. Storage policy: ops roles (staff + driver) can upload to revive-photos bucket
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add stage_key to job_milestones (canonical identifier for each stage)
--    Values: 'vehicle_intake','disassembly','welding','body_filler',
--            'painting','polishing','qc_finished','delivery'
-- ---------------------------------------------------------------------------
ALTER TABLE public.job_milestones
  ADD COLUMN IF NOT EXISTS stage_key TEXT;

-- Add unique constraint so each stage appears only once per job
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.job_milestones'::regclass
      AND conname = 'job_milestones_job_stage_unique'
  ) THEN
    ALTER TABLE public.job_milestones
      ADD CONSTRAINT job_milestones_job_stage_unique UNIQUE (job_id, stage_key);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Add job_id direct FK to job_milestone_photos
--    Allows single-query lookups by job without joining through milestones.
-- ---------------------------------------------------------------------------
ALTER TABLE public.job_milestone_photos
  ADD COLUMN IF NOT EXISTS job_id UUID REFERENCES public.repair_jobs(id) ON DELETE CASCADE;

-- Backfill job_id from the parent milestone (safe — no data yet in prod, but defensive)
UPDATE public.job_milestone_photos p
SET job_id = m.job_id
FROM public.job_milestones m
WHERE p.milestone_id = m.id
  AND p.job_id IS NULL;

-- Index for fast job-level photo queries
CREATE INDEX IF NOT EXISTS idx_milestone_photos_job_id
  ON public.job_milestone_photos(job_id);

CREATE INDEX IF NOT EXISTS idx_job_milestones_stage_key
  ON public.job_milestones(job_id, stage_key);

-- ---------------------------------------------------------------------------
-- 3. Extend advance_job_status to allow partner_staff and partner_driver
--    for their specific permitted transitions.
--
--    Permitted map (role → from → to):
--      partner_staff:  4_paid|3_booked → 5_admitted  (vehicle intake confirmation)
--      partner_staff:  5_admitted       → 6_in_progress
--      partner_staff:  6_in_progress    → 7_finished
--      partner_driver: 8_awaiting_delivery → 9_done  (delivery completion)
--
--    partner_driver is NOT allowed to admit (4→5); that is handled by
--    ops_complete_intake RPC which enforces photo evidence is attached first.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.advance_job_status(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.advance_job_status(
  p_job_id     UUID,
  p_new_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job           RECORD;
  v_caller_role   TEXT;
  v_partner_id    UUID;
  v_allowed       BOOLEAN := FALSE;
BEGIN
  -- Lock the job row to prevent race conditions
  SELECT * INTO v_job
    FROM public.repair_jobs
   WHERE id = p_job_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  -- Validate target status is a known value
  IF p_new_status NOT IN (
    '1_intake','2_estimated','3_booked','4_paid','5_admitted',
    '6_in_progress','7_finished','8_awaiting_delivery','9_done'
  ) THEN
    RAISE EXCEPTION 'Invalid status value: %', p_new_status;
  END IF;

  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  -- ── Role-based transition map ──────────────────────────────────────────────
  CASE v_caller_role

    WHEN 'master_admin' THEN
      v_allowed := TRUE; -- Admin: any valid transition

    WHEN 'customer' THEN
      v_allowed := (
        (v_job.status = '2_estimated' AND p_new_status = '3_booked') OR
        (v_job.status = '3_booked'    AND p_new_status = '4_paid')
      ) AND v_job.customer_id = auth.uid();

    WHEN 'partner_mechanic' THEN
      -- Must be the assigned partner
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      v_allowed := (
        (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
        (v_job.status = '5_admitted'            AND p_new_status = '6_in_progress') OR
        (v_job.status = '6_in_progress'         AND p_new_status = '7_finished') OR
        (v_job.status = '7_finished'            AND p_new_status = '8_awaiting_delivery')
      );

    WHEN 'partner_staff' THEN
      -- Must belong to the assigned partner
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      -- Staff can admit, start, and mark finished — but NOT set awaiting_delivery (partner_mechanic only)
      v_allowed := (
        (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
        (v_job.status = '5_admitted'            AND p_new_status = '6_in_progress') OR
        (v_job.status = '6_in_progress'         AND p_new_status = '7_finished')
      );

    WHEN 'partner_driver' THEN
      -- Driver can only complete final delivery (8→9)
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      v_allowed := (
        v_job.status = '8_awaiting_delivery' AND p_new_status = '9_done'
      );

    ELSE
      v_allowed := FALSE;
  END CASE;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transition % → % not allowed for role %',
      v_job.status, p_new_status, v_caller_role;
  END IF;

  -- ── If advancing 3_booked → 5_admitted, also book the slot if not yet booked ──
  IF p_new_status = '5_admitted' AND v_job.status = '3_booked' THEN
    IF v_job.scheduled_date IS NOT NULL THEN
      INSERT INTO public.partner_booked_slots (partner_id, job_id, slot_date)
      VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- ── Execute status update ──────────────────────────────────────────────────
  UPDATE public.repair_jobs
     SET status = p_new_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_job_status(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. RPC: ops_complete_intake
--    Called by driver/staff AFTER photos are uploaded to Supabase Storage.
--    Atomically:
--      a) Creates/upserts the 'vehicle_intake' milestone row
--      b) Inserts photo file_key records into job_milestone_photos
--      c) Advances repair_jobs.status to '5_admitted'
--    Allowed callers: partner_staff, partner_driver, partner_mechanic, master_admin
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ops_complete_intake(UUID, TEXT[]);

CREATE OR REPLACE FUNCTION public.ops_complete_intake(
  p_job_id    UUID,
  p_file_keys TEXT[]   -- array of storage file keys uploaded by client
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

  -- Only ops roles allowed
  IF v_caller_role NOT IN ('partner_staff', 'partner_driver', 'partner_mechanic', 'master_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized role: ' || COALESCE(v_caller_role,'null'));
  END IF;

  -- Validate photo array
  IF p_file_keys IS NULL OR array_length(p_file_keys, 1) IS NULL OR array_length(p_file_keys, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'At least one photo is required for vehicle intake.');
  END IF;

  -- Lock job
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  -- Verify job belongs to caller's partner (admin exempt)
  IF v_caller_role != 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not assigned to your workshop.');
  END IF;

  -- Verify valid source status
  IF v_job.status NOT IN ('3_booked', '4_paid') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Cannot admit from status: %s. Expected 3_booked or 4_paid.', v_job.status));
  END IF;

  -- Upsert intake milestone
  INSERT INTO public.job_milestones (job_id, milestone_name, stage_key, status, completed_by, completed_at)
  VALUES (p_job_id, 'Vehicle Intake', 'vehicle_intake', 'completed', auth.uid(), NOW())
  ON CONFLICT (job_id, stage_key) DO UPDATE
    SET status = 'completed', completed_by = auth.uid(), completed_at = NOW()
  RETURNING * INTO v_milestone;

  -- Insert photo records
  FOREACH v_file_key IN ARRAY p_file_keys LOOP
    INSERT INTO public.job_milestone_photos (milestone_id, job_id, uploaded_by, file_key)
    VALUES (v_milestone.id, p_job_id, auth.uid(), v_file_key);
  END LOOP;

  -- Slot booking if coming from 3_booked
  IF v_job.status = '3_booked' AND v_job.scheduled_date IS NOT NULL THEN
    INSERT INTO public.partner_booked_slots (partner_id, job_id, slot_date)
    VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Advance status
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

GRANT EXECUTE ON FUNCTION public.ops_complete_intake(UUID, TEXT[]) TO authenticated;


-- ---------------------------------------------------------------------------
-- 5. RPC: ops_complete_delivery
--    Called by driver AFTER delivery photos uploaded.
--    Atomically records 'delivery' milestone + photos + advances to 9_done.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ops_complete_delivery(UUID, TEXT[]);

CREATE OR REPLACE FUNCTION public.ops_complete_delivery(
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
    RETURN jsonb_build_object('success', false, 'error', 'Only drivers or admins can complete delivery.');
  END IF;

  IF p_file_keys IS NULL OR array_length(p_file_keys, 1) IS NULL OR array_length(p_file_keys, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'At least one delivery photo is required.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  IF v_caller_role != 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not assigned to your workshop.');
  END IF;

  IF v_job.status != '8_awaiting_delivery' THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Cannot complete delivery from status: %s. Expected 8_awaiting_delivery.', v_job.status));
  END IF;

  -- Upsert delivery milestone
  INSERT INTO public.job_milestones (job_id, milestone_name, stage_key, status, completed_by, completed_at)
  VALUES (p_job_id, 'Delivery / Pickup', 'delivery', 'completed', auth.uid(), NOW())
  ON CONFLICT (job_id, stage_key) DO UPDATE
    SET status = 'completed', completed_by = auth.uid(), completed_at = NOW()
  RETURNING * INTO v_milestone;

  -- Insert photo records
  FOREACH v_file_key IN ARRAY p_file_keys LOOP
    INSERT INTO public.job_milestone_photos (milestone_id, job_id, uploaded_by, file_key)
    VALUES (v_milestone.id, p_job_id, auth.uid(), v_file_key);
  END LOOP;

  -- Advance to 9_done
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

GRANT EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) TO authenticated;


-- ---------------------------------------------------------------------------
-- 6. Storage: Allow ops roles to upload/read from revive-photos bucket.
--    Policies live on storage.objects (Supabase RLS), NOT storage.policies.
--    File path convention enforced by app:
--      ops/{partner_id}/{job_id}/{stage_key}/{filename}
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Ops roles can upload milestone photos" ON storage.objects;
CREATE POLICY "Ops roles can upload milestone photos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('partner_staff', 'partner_driver')
    AND (storage.foldername(name))[1] = 'ops'
  );

DROP POLICY IF EXISTS "Ops roles can read milestone photos" ON storage.objects;
CREATE POLICY "Ops roles can read milestone photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('partner_staff', 'partner_driver')
    AND (storage.foldername(name))[1] = 'ops'
  );
