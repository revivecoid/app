-- =============================================================================
-- Migration: Auto Assignment Engine
-- =============================================================================

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS auto_assign_active BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_assign_priority INTEGER DEFAULT 999,
  ADD COLUMN IF NOT EXISTS auto_assign_capacity INTEGER DEFAULT 10;

CREATE TABLE IF NOT EXISTS public.auto_assign_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    is_active BOOLEAN DEFAULT false NOT NULL,
    match_location BOOLEAN DEFAULT true NOT NULL,
    mode TEXT DEFAULT 'strict_priority' NOT NULL CHECK (mode IN ('fill_first', 'strict_priority', 'round_robin')),
    last_partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO public.auto_assign_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.auto_assign_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin manage auto assign settings" ON public.auto_assign_settings FOR ALL TO authenticated USING (public.is_master_admin()) WITH CHECK (public.is_master_admin());
CREATE POLICY "Anyone read auto assign settings" ON public.auto_assign_settings FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.get_partner_active_job_count(p_partner_id UUID)
RETURNS INTEGER LANGUAGE sql SECURITY DEFINER AS $$
  SELECT count(*)::INT FROM public.repair_jobs
  WHERE partner_id = p_partner_id AND status IN ('3_booked', '3_inspected', '4_paid', '5_admitted', '6_in_progress', '7_finished', '8_awaiting_delivery');
$$;

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

  IF v_settings.mode IN ('fill_first', 'strict_priority') THEN
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'round_robin' THEN
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
GRANT EXECUTE ON FUNCTION public.execute_auto_assign(UUID) TO authenticated;
