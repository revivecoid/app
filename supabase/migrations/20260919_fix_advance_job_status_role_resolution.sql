-- =============================================================================
-- Fix role resolution in advance_job_status
-- Date: 2026-09-19
--
-- Symptom:
--   Booking a job failed with
--     Transition 2_estimated → 3_booked not allowed for role <NULL>  (P0001)
--
-- Cause:
--   The guard resolved the caller's role ONLY from the JWT:
--     v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
--   handle_new_user() provisions public.profiles.role but does NOT write
--   app_metadata.role. On this project 6 of 11 users — every customer — have
--   app_metadata.role = NULL while profiles.role = 'customer'. So v_caller_role
--   was NULL, the CASE fell to ELSE, v_allowed stayed FALSE, and the exception
--   fired for every legitimate customer booking.
--
-- Fix:
--   app_metadata.role first (preserves partner_mechanic / partner_staff /
--   partner_driver / master_admin exactly as today), then fall back to
--   public.profiles.role when the JWT carries no role. This deliberately does
--   NOT make profiles authoritative, because 'partner_mechanic' exists only in
--   app_metadata — inverting the precedence would silently revoke access for
--   the users currently holding it. Nobody's permissions change; the NULL case
--   is simply resolved instead of denied.
--
--   Both sources are allowed by the project's auth rule. user_metadata is NOT
--   consulted (self-writable, privilege-escalation vector).
--
--   partner_id likewise: JWT app_metadata.partner_id is the tenant-isolation
--   source of truth, with profiles.partner_id as fallback only.
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

  CASE v_caller_role

    WHEN 'master_admin' THEN
      v_allowed := TRUE;

    WHEN 'customer' THEN
      v_allowed := (
        (v_job.status = '2_estimated'  AND p_new_status = '3_booked') OR
        (v_job.status = '3_inspected'  AND p_new_status = '4_paid')
      ) AND v_job.customer_id = auth.uid();

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


-- ---------------------------------------------------------------------------
-- Verify resolution for every existing user (impersonating each JWT is not
-- possible here, so check the underlying sources directly).
-- ---------------------------------------------------------------------------
SELECT u.id,
       COALESCE(u.raw_app_meta_data ->> 'role',
                p.role::text)                       AS resolved_role,
       u.raw_app_meta_data ->> 'role'               AS jwt_role,
       p.role::text                                 AS profile_role
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
 ORDER BY resolved_role;
