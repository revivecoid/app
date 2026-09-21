-- =============================================================================
-- Widen ops_complete_delivery to partner_staff
-- Date: 2026-09-21
--
-- Why
-- ---
-- Staff are the ones who hand the car back to the customer, so excluding them
-- from the delivery module was wrong. Under ops_view_mode = 'all_access' the UI
-- already offered them the delivery stage and the RPC refused it — a visible
-- stage that always fails. With this, the refusal matches the UI.
--
-- Scope
-- -----
-- Generated from the LIVE pg_get_functiondef so exactly the role list and its
-- error message change; the tenant check, the 8_awaiting_delivery guard, the
-- milestone upsert and the 9_done advance are preserved verbatim.
--
-- Required companion change (client): the 'delivery' stage's allowedRoles in
-- ops_stage_photo_screen.dart must also admit partner_staff, or the button stays
-- hidden under ops_view_mode = 'original_role'. Both are needed: this RPC gates
-- the server, that list gates the UI.
--
-- Idempotent: CREATE OR REPLACE, and the ACL is re-asserted at the end.
-- =============================================================================

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

-- EXECUTE is granted to PUBLIC on a newly created function regardless of the
-- REVOKE ... FROM anon that looks sufficient, so revoke from PUBLIC explicitly.
REVOKE EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_complete_delivery(UUID, TEXT[]) TO authenticated;
