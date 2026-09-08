-- ─────────────────────────────────────────────────────────────────────────────
-- Fix 1: notification trigger — correct net.http_post call signature
--
-- Problem: net.http_post named-parameter `body` expects TEXT, but the trigger
-- was passing a JSONB value directly. pg_net also requires positional args in
-- some versions. Cast body to ::text to match all versions.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key  TEXT;
  payload           JSONB;
  request_id        BIGINT;
BEGIN
  -- Only trigger if the status has actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN

    -- Read credentials from Supabase Vault / app.settings
    -- Set these in Dashboard → Settings → Vault (or Project Settings → API)
    edge_function_url := current_setting('app.supabase_url', true)
                          || '/functions/v1/send-notification';
    service_role_key  := current_setting('app.service_role_key', true);

    -- If credentials not configured, skip webhook silently
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

    -- net.http_post: body must be TEXT (cast jsonb → text)
    BEGIN
      SELECT net.http_post(
        url     := edge_function_url,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || service_role_key
        )::jsonb,
        body    := payload::text    -- ← was missing ::text cast
      ) INTO request_id;
    EXCEPTION WHEN others THEN
      -- Webhook failure must never block the job update
      RAISE WARNING 'handle_job_status_change: webhook error (non-fatal): %', SQLERRM;
    END;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create the trigger (DROP IF EXISTS handles idempotency)
DROP TRIGGER IF EXISTS on_repair_job_status_change ON public.repair_jobs;
CREATE TRIGGER on_repair_job_status_change
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_job_status_change();


-- ─────────────────────────────────────────────────────────────────────────────
-- Fix 2: admin_assign_job RPC
--
-- SECURITY DEFINER + SET LOCAL session_replication_role = 'replica' disables
-- per-row triggers for this transaction so the webhook trigger doesn't fire
-- during admin manual overrides (avoids the pg_net dependency entirely for
-- admin actions — the partner app already handles its own push notifications).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_assign_job(
  p_job_id    UUID,
  p_partner_id UUID,
  p_status    TEXT DEFAULT '3_booked'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Disable row-level triggers for this session to bypass the webhook trigger.
  -- The trigger still fires for normal customer/partner status changes.
  SET LOCAL session_replication_role = 'replica';

  UPDATE public.repair_jobs
     SET partner_id = p_partner_id,
         status     = p_status
   WHERE id = p_job_id;

  RESET session_replication_role;
END;
$$;

-- Allow authenticated admins to call this function
GRANT EXECUTE ON FUNCTION public.admin_assign_job(UUID, UUID, TEXT)
  TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- Fix 3: admin_unassign_job RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_unassign_job(
  p_job_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET LOCAL session_replication_role = 'replica';

  UPDATE public.repair_jobs
     SET partner_id = NULL,
         status     = '2_estimated'
   WHERE id = p_job_id;

  RESET session_replication_role;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_unassign_job(UUID)
  TO authenticated;
