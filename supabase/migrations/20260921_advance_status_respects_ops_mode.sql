-- =============================================================================
-- advance_job_status: honour ops_view_mode for ops operators
-- Date: 2026-09-21
--
-- Why
-- ---
-- The stage-photo gate and the status-transition gate disagreed. ops_may_act_on_stage
-- lets any operator act on any stage under all_access, but advance_job_status kept
-- mode-blind per-role transition lists in which a driver may only do
-- 8_awaiting_delivery -> 9_done. So a driver completing Disassembly had the
-- milestone WRITE succeed and the status advance REFUSED, leaving the job at
-- 5_admitted with 'disassembly' marked complete. Welding, body filler, painting,
-- polishing and QC all require 6_in_progress, so the job could not progress at all.
--
-- Both workshops are on all_access, so this fires today, not in theory.
--
-- What this does
-- --------------
-- One substitution in the live body: the ELSE before the role CASE becomes an
-- ELSIF permitting the ops transitions when the workshop is on all_access. The
-- transition set is the union of what the three ops roles could each do, so
-- all_access genuinely means act-on-all rather than "act on the stages we forgot
-- to gate".
--
-- What it does NOT do
-- -------------------
--   * customer: unchanged, still only 2_estimated->3_booked and 3_inspected->4_paid,
--     still gated on ownership.
--   * original_role / view_all_act_own: unchanged per-role lists. Consistent, since
--     the stage-write gate refuses the milestone there anyway.
--   * cross-tenant: still refused by the existing RAISE, because the new branch
--     requires v_job.partner_id to match the caller's own workshop.
--   * the half-commit itself is still possible if a write lands and the advance is
--     refused for another reason. Wrapping the two in one transaction is a separate
--     change, deliberately not made here.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. The transition set for all_access, as one place to read it
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_all_access_transition(
  p_from TEXT,
  p_to   TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- The caller's workshop must be on all_access. Reading the mode from the JWT's
  -- partner_id keeps this a pure function of the session, with no extra argument
  -- the caller could lie about.
  SELECT COALESCE((
           SELECT p.ops_view_mode
             FROM public.partners p
            WHERE p.id = (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID
         ), '') = 'all_access'
     AND (
       (p_from IN ('3_booked', '4_paid') AND p_to = '5_admitted')          OR
       (p_from IN ('4_paid', '5_admitted') AND p_to = '6_in_progress')     OR
       (p_from = '6_in_progress'          AND p_to = '7_finished')         OR
       (p_from = '7_finished'             AND p_to = '8_awaiting_delivery') OR
       (p_from = '8_awaiting_delivery'    AND p_to = '9_done')
     );
$$;

REVOKE EXECUTE ON FUNCTION public.ops_all_access_transition(TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_all_access_transition(TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. The function, generated from its live definition
-- ---------------------------------------------------------------------------

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
  -- all_access means act-on-all, for transitions as well as stage photos. Without
  -- this the UI offered a stage whose status advance was then refused, and the
  -- milestone committed anyway: the job ended up half-advanced and stuck, with
  -- every later stage gated on a status it could never reach.
  --
  -- Scoped to ops roles on their OWN workshop's job. A cross-tenant caller falls
  -- through to the CASE below and still hits its RAISE. The customer and
  -- ownership paths above are untouched.
  ELSIF v_caller_role IN ('partner_staff', 'partner_driver', 'partner_mechanic')
        AND v_job.partner_id IS NOT DISTINCT FROM v_partner_id
        AND public.ops_all_access_transition(v_job.status, p_new_status) THEN
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

-- ---------------------------------------------------------------------------
-- 3. Verify (last result set only -- the Management API returns just that one)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT pg_get_functiondef(p.oid) LIKE '%ops_all_access_transition%'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='advance_job_status')            AS advance_gated,
  (SELECT pg_get_functiondef(p.oid) LIKE '%v_job.status = ''8_awaiting_delivery'' AND p_new_status = ''9_done''%'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='advance_job_status')            AS driver_branch_intact,
  (SELECT pg_get_functiondef(p.oid) LIKE '%v_job.status = ''3_inspected'' AND p_new_status = ''4_paid''%'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='advance_job_status')            AS customer_branch_intact,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='advance_job_status')            AS overload_count;
