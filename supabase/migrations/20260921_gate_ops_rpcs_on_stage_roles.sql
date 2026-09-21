-- =============================================================================
-- Gate the ops intake/delivery RPCs on ops_stage_roles
-- Date: 2026-09-21
--
-- Both RPCs are SECURITY DEFINER, so they bypass RLS and the restrictive policies
-- added in 20260921_ops_stage_role_enforcement.sql do NOT apply to them. Their
-- own role-list check is a hardcoded copy of the same knowledge, which is how the
-- two drifted apart in the first place: the delivery RPC excluded partner_staff
-- while the UI offered them the stage.
--
-- Each function body below was GENERATED from its live pg_get_functiondef, with a
-- single insertion: a call to public.ops_may_act_on_stage(p_job_id, '<stage>')
-- placed immediately AFTER the tenant check and BEFORE the status guard. So the
-- tenant rule still produces its own clearer message for a cross-workshop caller,
-- and everything else in the body is byte-for-byte what is running today.
--
-- The pre-existing role-list check is deliberately kept:
--   * it names the offending role in its error, which a bare boolean cannot;
--   * it keeps both functions safe if ops_stage_roles is ever empty;
--   * under all_access the helper returns true for any operator, so they agree.
--
-- Idempotent: CREATE OR REPLACE plus a re-asserted ACL.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ops_complete_intake
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_complete_intake(p_job_id uuid, p_file_keys text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- Role gate, from the same table the RLS policies consult, so the UI, the
  -- policies and this RPC can never disagree about who may complete a stage.
  IF NOT public.ops_may_act_on_stage(p_job_id, 'vehicle_intake') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Your role (%s) may not complete the %s stage at this workshop.',
                      COALESCE(v_caller_role, 'null'), 'vehicle_intake'));
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
$function$;
REVOKE EXECUTE ON FUNCTION public.ops_complete_intake(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_complete_intake(UUID, TEXT[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- ops_complete_delivery
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_complete_delivery(p_job_id uuid, p_file_keys text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    RETURN jsonb_build_object('success', false,
      'error', format('Only staff, drivers, mechanics or admins can complete delivery. Your role: %s', COALESCE(v_caller_role, 'null')));
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

  -- Role gate, from the same table the RLS policies consult, so the UI, the
  -- policies and this RPC can never disagree about who may complete a stage.
  IF NOT public.ops_may_act_on_stage(p_job_id, 'delivery') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Your role (%s) may not complete the %s stage at this workshop.',
                      COALESCE(v_caller_role, 'null'), 'delivery'));
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
$function$;
REVOKE EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- Verify (last result set only -- the Management API returns just that one)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('ops_complete_intake','ops_complete_delivery')
      AND pg_get_functiondef(p.oid) LIKE '%ops_may_act_on_stage%')       AS gated_functions,
  (SELECT count(*) FROM public.ops_stage_roles)                          AS stage_roles,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname='public' AND policyname LIKE 'ops stage role gate%') AS gate_policies;
