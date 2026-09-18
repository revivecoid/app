-- =============================================================================
-- Migration: Fix handle_job_status_change trigger + admin RPC skip_webhook flag
-- Date: 2026-09-18
-- Problems:
--   1. net.http_post called with named params — newer pg_net uses positional.
--      The EXCEPTION block should have caught this but the error escapes
--      because pg_net raises it as a function-not-found (42883) before the
--      block executes, which propagates up and aborts the transaction.
--   2. admin_assign_job (new migration) used set_config(...,'true',true) but
--      the trigger checks for 'on' — mismatch means skip never fires.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Rebuild handle_job_status_change
--    - Accept both 'on' and 'true' for the skip flag
--    - Use PERFORM + positional args for net.http_post (pg_net ≥0.8 compat)
--    - Wrap entire net call in EXCEPTION so it can never block a job update
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key  TEXT;
  payload           JSONB;
  skip_flag         TEXT;
BEGIN
  BEGIN
    skip_flag := current_setting('app.skip_webhook', true);
  EXCEPTION WHEN OTHERS THEN
    skip_flag := 'off';
  END;

  -- Accept both 'on' and 'true' — different callers use different values
  IF skip_flag IN ('on', 'true') THEN
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status THEN
    edge_function_url := current_setting('app.supabase_url', true)
                          || '/functions/v1/send-notification';
    service_role_key  := current_setting('app.service_role_key', true);

    -- Skip silently if credentials not configured
    IF edge_function_url IS NULL OR service_role_key IS NULL
      OR edge_function_url = '/functions/v1/send-notification' THEN
      RETURN NEW;
    END IF;

    payload := jsonb_build_object(
      'job_id',      NEW.id,
      'customer_id', NEW.customer_id,
      'old_status',  OLD.status,
      'new_status',  NEW.status
    );

    -- Use PERFORM + positional args (pg_net ≥0.8 dropped named param support)
    BEGIN
      PERFORM net.http_post(
        edge_function_url,
        payload::text,
        'application/json',
        jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || service_role_key
        )
      );
    EXCEPTION WHEN OTHERS THEN
      -- Webhook failure must NEVER block the job status update
      RAISE WARNING 'handle_job_status_change: webhook error (non-fatal): %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public, pg_temp;


-- ---------------------------------------------------------------------------
-- 2. Rebuild admin_assign_job — use SET LOCAL 'on' to match trigger check,
--    include 3_inspected in valid status list.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_assign_job(
  p_job_id     UUID,
  p_partner_id UUID,
  p_status     TEXT DEFAULT '3_booked'
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
  SET LOCAL app.skip_webhook = 'on';
  UPDATE public.repair_jobs
     SET partner_id        = p_partner_id,
         status            = p_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_job(UUID, UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. Rebuild admin_unassign_job — use SET LOCAL 'on', preserve booking state.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_unassign_job(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_job RECORD;
BEGIN
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Job not found: %', p_job_id; END IF;
  SET LOCAL app.skip_webhook = 'on';
  UPDATE public.repair_jobs
     SET partner_id        = NULL,
         status            = CASE
                               WHEN v_job.scheduled_date IS NOT NULL THEN '3_booked'
                               ELSE '2_estimated'
                             END,
         status_changed_at = NOW()
   WHERE id = p_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_unassign_job(UUID) TO authenticated;
