-- =============================================================================
-- Let job ownership grant customer transitions, regardless of the caller's role
-- Date: 2026-09-19
--
-- Supersedes the role-resolution fix in
-- 20260919_fix_advance_job_status_role_resolution.sql (that fix is still needed
-- — it resolved the NULL role for plain customers — but it is not sufficient).
--
-- Remaining defect:
--   A partner mechanic may also be a customer of another workshop (confirmed as
--   intended). Such a user has profiles.role = 'customer' and
--   app_metadata.role = 'partner_mechanic' + partner_id. Because app_metadata
--   takes precedence, they always resolve to partner_mechanic, so booking their
--   own car takes the partner branch:
--
--     WHEN 'partner_mechanic' THEN
--       IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
--         RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
--
--   Their own job has partner_id = NULL (no workshop assigned at booking time),
--   so that guard fires and the booking is refused. Reproduced live:
--     HTTP 400  forbidden: this job is not assigned to your workshop
--     job stayed at 2_estimated
--
-- Fix:
--   Decide the action by OWNERSHIP, not by role. If the caller owns the job,
--   they are that job's customer and get the two customer transitions. Role is
--   only consulted when they are not the owner.
--
--   This cannot escalate: the ownership branch grants only
--   2_estimated -> 3_booked and 3_inspected -> 4_paid, and only on a job whose
--   customer_id = auth.uid(). No partner or admin power is reachable through it,
--   and partner_mechanic acting on a workshop job still goes through the role
--   branch exactly as before.
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
      INSERT INTO public.partner_booked_slots (partner_id, job_id, slot_date)
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

GRANT EXECUTE ON FUNCTION public.advance_job_status(uuid, text) TO authenticated;
