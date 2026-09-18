-- =============================================================================
-- Migration: Admin active jobs RPC + assignment fixes for new workflow
-- Date: 2026-09-18
-- Problems fixed:
--   1. get_admin_active_jobs RPC was called but never created — admin job board
--      showed nothing. Create it now to return ALL non-terminal jobs.
--   2. admin_assign_job valid status list didn't include '3_inspected'.
--   3. admin_unassign_job reset to '2_estimated'; now resets to '3_booked'
--      if the job had a scheduled_date (booking already confirmed).
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Create get_admin_active_jobs RPC
--    Returns all non-terminal jobs with customer, vehicle, partner info.
--    SECURITY DEFINER so it bypasses RLS (admin-only via is_master_admin()).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_admin_active_jobs();

CREATE OR REPLACE FUNCTION public.get_admin_active_jobs()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'created_at') DESC), '[]'::jsonb)
    FROM (
      SELECT jsonb_build_object(
        'id',             rj.id,
        'status',         rj.status,
        'created_at',     rj.created_at,
        'scheduled_date', rj.scheduled_date,
        'partner_id',     rj.partner_id,
        'final_cost',     rj.final_cost,
        'customer_name',  COALESCE(p.full_name, 'Unknown'),
        'customer_id',    rj.customer_id,
        'make',           v.make,
        'model',          v.model,
        'license_plate',  v.license_plate,
        'partner_name',   COALESCE(par.shop_name, 'Unassigned')
      ) AS row_data
      FROM public.repair_jobs rj
      LEFT JOIN public.profiles p   ON p.id  = rj.customer_id
      LEFT JOIN public.vehicles v   ON v.id  = rj.vehicle_id
      LEFT JOIN public.partners par ON par.id = rj.partner_id
      WHERE rj.status NOT IN ('0_cancelled', '9_done')
    ) sub
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_active_jobs() TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. Fix admin_assign_job — add '3_inspected' to valid status list,
--    and allow assignment regardless of current status (admin override).
--    Keeps existing behaviour but with expanded status enum.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_assign_job(
  p_job_id    UUID,
  p_partner_id UUID,
  p_status    TEXT DEFAULT '3_booked'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  IF p_status NOT IN (
    '0_cancelled','1_intake','2_estimated','3_booked','3_inspected',
    '4_paid','5_admitted','6_in_progress','7_finished','8_awaiting_delivery','9_done'
  ) THEN
    RAISE EXCEPTION 'invalid status value: %', p_status;
  END IF;

  -- Skip webhook trigger during assignment
  PERFORM set_config('app.skip_webhook', 'true', true);

  UPDATE public.repair_jobs
     SET partner_id        = p_partner_id,
         status            = p_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;

  PERFORM set_config('app.skip_webhook', 'false', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_job(UUID, UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. Fix admin_unassign_job — reset status to '3_booked' if job had a
--    scheduled_date (booking was confirmed), else '2_estimated'.
--    Previously always reset to '2_estimated' which was wrong post-booking.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_unassign_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job RECORD;
BEGIN
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  PERFORM set_config('app.skip_webhook', 'true', true);

  UPDATE public.repair_jobs
     SET partner_id        = NULL,
         -- If booking was confirmed (has scheduled_date), revert to 3_booked
         -- so the booking info is preserved. Otherwise back to 2_estimated.
         status            = CASE
                               WHEN v_job.scheduled_date IS NOT NULL THEN '3_booked'
                               ELSE '2_estimated'
                             END,
         status_changed_at = NOW()
   WHERE id = p_job_id;

  PERFORM set_config('app.skip_webhook', 'false', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_unassign_job(UUID) TO authenticated;
