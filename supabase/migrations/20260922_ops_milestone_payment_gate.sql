-- Repair may not start before the customer has PAID (ops milestone gate).
--
-- Companion to 20260922_gate_repair_on_payment.sql, which removed the
-- 5_admitted -> 6_in_progress edge from advance_job_status. That alone was not
-- enough: the ops stage screen inserts the job_milestones row and then calls
-- advance_job_status as two separate statements (ops_stage_photo_screen.dart
-- ~line 296 then ~line 314), with no transaction around them. Refusing only the
-- status change would leave `disassembly` committed while the job still sat at
-- 5_admitted — and since welding/body_filler/painting/polishing/qc_finished all
-- require 6_in_progress, the job would be permanently stuck.
--
-- This function is the single choke point for every ops milestone write: three
-- restrictive policies depend on it (job_milestones INSERT and UPDATE,
-- job_milestone_photos INSERT). Blocking here therefore stops the write before it
-- happens, so the refusal is atomic from the operator's point of view.
--
-- Generated from the live body by targeted substitution so nothing else drifts.

CREATE OR REPLACE FUNCTION public.ops_may_act_on_stage(p_job_id uuid, p_stage_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_role       TEXT;
  v_partner    UUID;
  v_mode       TEXT;
  v_job_status TEXT;
BEGIN
  v_role    := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  -- A platform admin is outside the workshop model entirely.
  IF v_role = 'master_admin' THEN
    RETURN TRUE;
  END IF;

  -- Not an ops operator at all (customer, anon, absent claim).
  IF v_role IS NULL OR v_role NOT IN ('partner_staff', 'partner_driver', 'partner_mechanic') THEN
    RETURN FALSE;
  END IF;

  -- Must be THIS workshop's job. Tenant isolation is not softened by the mode.
  -- The job's status is read in the same pass, because it decides whether repair
  -- work may be recorded at all.
  SELECT r.status INTO v_job_status
    FROM public.repair_jobs r
   WHERE r.id = p_job_id AND r.partner_id = v_partner;

  IF v_partner IS NULL OR v_job_status IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Repair may not begin before the customer has PAID. Every repair stage
  -- (disassembly onward) writes a milestone straight from the ops app and only
  -- afterwards asks advance_job_status to move the job, as two separate calls —
  -- so gating only the status change would commit the milestone and leave the job
  -- behind it, making every later stage unreachable. Refusing the milestone write
  -- here is the one place that keeps the two in step.
  --
  -- `vehicle_intake` is the sole stage that runs earlier: it admits the car, which
  -- is what makes the invoice (and therefore payment) possible. `master_admin` was
  -- already allowed through above, matching advance_job_status's admin override.
  IF p_stage_key <> 'vehicle_intake'
     AND v_job_status NOT IN ('4_paid', '6_in_progress', '7_finished',
                              '8_awaiting_delivery', '9_done') THEN
    RETURN FALSE;
  END IF;

  SELECT p.ops_view_mode INTO v_mode
    FROM public.partners p WHERE p.id = v_partner;

  -- An unreadable or missing row restricts rather than permits.
  IF v_mode = 'all_access' THEN
    RETURN TRUE;
  END IF;

  -- view_all_act_own and original_role both restrict ACTING to the stage's own
  -- role list. They differ only in what the UI SHOWS, which is a presentation
  -- concern this function deliberately does not police.
  RETURN EXISTS (
    SELECT 1 FROM public.ops_stage_roles sr
     WHERE sr.stage_key = p_stage_key AND sr.role = v_role
  );
END;
$function$
