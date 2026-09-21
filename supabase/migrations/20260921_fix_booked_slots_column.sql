-- =============================================================================
-- Fix: partner_booked_slots column name in advance_job_status
-- Date: 2026-09-21
--
-- advance_job_status inserts into partner_booked_slots when a job is admitted
-- straight from 3_booked. It named a column `slot_date`, but that column does not
-- exist — partner_booked_slots has `booked_date`. Any 3_booked -> 5_admitted
-- transition with a scheduled_date would therefore have raised
--   42703: column "slot_date" of relation "partner_booked_slots" does not exist
-- i.e. admitting a booked vehicle would fail at the till. It had not been
-- exercised yet, so it was a live landmine rather than a reported fault.
--
-- The body below is the CURRENT LIVE definition with exactly one change:
-- `slot_date` -> `booked_date`. It is not a rewrite or a replay of an older
-- migration — advance_job_status has been superseded twice
-- (20260919_fix_advance_job_status_role_resolution, 20260919_fix_advance_status_ownership)
-- and this regresses none of that: the 3_inspected workflow statuses and the
-- profiles-based caller-role fallback are both preserved verbatim.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.advance_job_status(p_job_id uuid, p_new_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job           RECORD;
  v_caller_role   TEXT;
  v_partner_id    UUID;
  v_allowed       BOOLEAN := FALSE;
  v_is_owner      BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_job
    FROM public.repair_jobs
   WHERE id = p_job_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  IF p_new_status NOT IN (
    '0_cancelled','1_intake','2_estimated','3_booked','3_inspected',
    '4_paid','5_admitted','6_in_progress','7_finished','8_awaiting_delivery','9_done'
  ) THEN
    RAISE EXCEPTION 'Invalid status value: %', p_new_status;
  END IF;

  -- Role: JWT app_metadata first, then the DB profile. Never user_metadata.
  v_caller_role := COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'role'),
    (SELECT p.role::TEXT FROM public.profiles p WHERE p.id = auth.uid())
  );

  -- Tenant: JWT partner_id is authoritative, profile is the fallback.
  v_partner_id := COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID,
    (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid())
  );

  v_is_owner := (v_job.customer_id = auth.uid());

  -- Ownership first: a partner mechanic may also be a customer of another
  -- workshop, so their own job must not be judged by their workshop role.
  IF v_is_owner AND (
       (v_job.status = '2_estimated' AND p_new_status = '3_booked') OR
       (v_job.status = '3_inspected' AND p_new_status = '4_paid')
     ) THEN
    v_allowed := TRUE;
  ELSE
    CASE v_caller_role

      WHEN 'master_admin' THEN
        v_allowed := TRUE;

      WHEN 'customer' THEN
        v_allowed := (
          (v_job.status = '2_estimated'  AND p_new_status = '3_booked') OR
          (v_job.status = '3_inspected'  AND p_new_status = '4_paid')
        ) AND v_is_owner;

      WHEN 'partner_mechanic' THEN
        IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
          RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
        END IF;
        v_allowed := (
          (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
          (v_job.status = '4_paid'               AND p_new_status = '6_in_progress') OR
          (v_job.status = '5_admitted'           AND p_new_status = '6_in_progress') OR
          (v_job.status = '6_in_progress'        AND p_new_status = '7_finished') OR
          (v_job.status = '7_finished'           AND p_new_status = '8_awaiting_delivery')
        );

      WHEN 'partner_staff' THEN
        IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
          RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
        END IF;
        v_allowed := (
          (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
          (v_job.status = '4_paid'               AND p_new_status = '6_in_progress') OR
          (v_job.status = '5_admitted'           AND p_new_status = '6_in_progress') OR
          (v_job.status = '6_in_progress'        AND p_new_status = '7_finished')
        );

      WHEN 'partner_driver' THEN
        IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
          RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
        END IF;
        v_allowed := (
          v_job.status = '8_awaiting_delivery' AND p_new_status = '9_done'
        );

      ELSE
        v_allowed := FALSE;
    END CASE;
  END IF;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transition % → % not allowed for role %',
      v_job.status, p_new_status, COALESCE(v_caller_role, '<unresolved>');
  END IF;

  IF p_new_status = '5_admitted' AND v_job.status = '3_booked' THEN
    IF v_job.scheduled_date IS NOT NULL THEN
      INSERT INTO public.partner_booked_slots (partner_id, job_id, booked_date)
      VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  UPDATE public.repair_jobs
     SET status = p_new_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;

END;
$function$;
