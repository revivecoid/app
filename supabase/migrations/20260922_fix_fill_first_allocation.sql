-- =============================================================================
-- Migration: Fix fill_first allocation strategy
-- -----------------------------------------------------------------------------
-- fill_first was previously implemented as "fill the top workshop, then let it
-- drain to 0 before touching it again" (drain-to-empty). That is wrong.
--
-- Correct semantics:
--   fill_first  = round-robin rotation across the priority queue, with ONE
--                 override: a higher priority workshop (lower auto_assign_priority
--                 than the rotation's next pick) that is currently EMPTY
--                 (0 active jobs) takes that single job instead.
--                 As soon as it holds a job it is no longer empty and the
--                 rotation resumes normally.
--   strict_priority = always the highest priority workshop with ANY open slot.
--   round_robin     = pure even distribution in priority order.
-- =============================================================================

ALTER TABLE public.partners DROP COLUMN IF EXISTS auto_assign_is_draining;

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

  IF v_settings.mode = 'strict_priority' THEN
    -- Highest priority workshop with ANY open slot takes the job.
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'fill_first' THEN
    -- Round-robin rotation, overridden by a higher priority workshop only while
    -- that workshop is completely empty.
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_priority, p.auto_assign_capacity,
             public.get_partner_active_job_count(p.id) AS current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) AS rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS (
      SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id
    ),
    rotation_pick AS (
      SELECT op.id, op.auto_assign_priority, op.rn
      FROM ordered_partners op
      WHERE op.current_jobs < op.auto_assign_capacity
      ORDER BY CASE
                 WHEN (SELECT rn FROM last_partner) IS NOT NULL
                      AND op.rn > (SELECT rn FROM last_partner) THEN 0
                 ELSE 1
               END, op.rn ASC
      LIMIT 1
    )
    SELECT c.id INTO v_assigned_partner_id
    FROM (
      -- 1st choice: an empty workshop with better priority than the rotation pick
      SELECT op.id, 1 AS pref, op.auto_assign_priority AS pr, op.rn
      FROM ordered_partners op
      WHERE op.current_jobs = 0
        AND op.current_jobs < op.auto_assign_capacity
        AND op.auto_assign_priority < (SELECT auto_assign_priority FROM rotation_pick)
      UNION ALL
      -- 2nd choice: the rotation pick itself
      SELECT rp.id, 2 AS pref, rp.auto_assign_priority AS pr, rp.rn
      FROM rotation_pick rp
    ) c
    ORDER BY c.pref ASC, c.pr ASC, c.rn ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'round_robin' THEN
    -- Even distribution in priority order, one job per workshop per cycle.
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_capacity,
             public.get_partner_active_job_count(p.id) AS current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) AS rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS (
      SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id
    )
    SELECT op.id INTO v_assigned_partner_id
    FROM ordered_partners op
    WHERE op.current_jobs < op.auto_assign_capacity
    ORDER BY CASE
               WHEN (SELECT rn FROM last_partner) IS NOT NULL
                    AND op.rn > (SELECT rn FROM last_partner) THEN 0
               ELSE 1
             END, op.rn ASC
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
