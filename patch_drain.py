import urllib.request, json
PAT = "sbp_fcd9960b5c5c6e16b4e5653dee494efdee237441"
MGMT = "https://api.supabase.com/v1/projects/ahaospjkkuetkaixwzzz/database/query"

sql = """
ALTER TABLE public.partners ADD COLUMN IF NOT EXISTS auto_assign_is_draining BOOLEAN DEFAULT false;

CREATE OR REPLACE FUNCTION public.execute_auto_assign(p_job_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_job RECORD;
  v_settings RECORD;
  v_assigned_partner_id UUID := NULL;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Job not found'); END IF;
  IF v_job.partner_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Job already assigned'); END IF;
  
  SELECT * INTO v_settings FROM public.auto_assign_settings WHERE id = 1;
  IF NOT v_settings.is_active THEN RETURN jsonb_build_object('success', false, 'error', 'Auto-assign is disabled'); END IF;

  -- 1. Reset draining status for any workshop that has completely emptied
  UPDATE public.partners p
  SET auto_assign_is_draining = false
  WHERE p.auto_assign_is_draining = true 
    AND public.get_partner_active_job_count(p.id) = 0;

  -- 2. Execute Strategy
  IF v_settings.mode = 'strict_priority' THEN
    -- Option 1: Always fill the highest priority with ANY open slot
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'fill_first' THEN
    -- Option 2: Fill to capacity, then let it completely drain to 0 before giving it jobs again
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND p.auto_assign_is_draining = false
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'round_robin' THEN
    -- Option 3: Evenly distribute
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_capacity, public.get_partner_active_job_count(p.id) as current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) as rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS ( SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id )
    SELECT op.id INTO v_assigned_partner_id
    FROM ordered_partners op
    WHERE op.current_jobs < op.auto_assign_capacity
    ORDER BY CASE WHEN (SELECT rn FROM last_partner) IS NOT NULL AND op.rn > (SELECT rn FROM last_partner) THEN 0 ELSE 1 END, op.rn ASC
    LIMIT 1;
  END IF;

  IF v_assigned_partner_id IS NOT NULL THEN
    -- Flag if the chosen partner just hit capacity (only matters for 'fill_first' mode, but safe to track globally)
    IF (public.get_partner_active_job_count(v_assigned_partner_id) + 1) >= (SELECT auto_assign_capacity FROM public.partners WHERE id = v_assigned_partner_id) THEN
      UPDATE public.partners SET auto_assign_is_draining = true WHERE id = v_assigned_partner_id;
    END IF;

    -- Assign job
    PERFORM set_config('app.skip_webhook', 'true', true);
    UPDATE public.repair_jobs SET partner_id = v_assigned_partner_id, status_changed_at = NOW() WHERE id = p_job_id;
    PERFORM set_config('app.skip_webhook', 'false', true);
    
    UPDATE public.auto_assign_settings SET last_partner_id = v_assigned_partner_id WHERE id = 1;
    RETURN jsonb_build_object('success', true, 'partner_id', v_assigned_partner_id);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'No eligible partner found with capacity');
  END IF;
END;
$$;
"""

r = urllib.request.Request(MGMT, data=json.dumps({"query": sql}).encode(), headers={"Authorization":"Bearer "+PAT,"Content-Type":"application/json"}, method="POST")
with urllib.request.urlopen(r) as resp:
    print(json.loads(resp.read().decode()))
