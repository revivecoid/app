-- Migration: Fix net.http_post call in notification trigger

CREATE EXTENSION IF NOT EXISTS pg_net;

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
    edge_function_url := current_setting('app.supabase_url', true)
                          || '/functions/v1/send-notification';
    service_role_key  := current_setting('app.service_role_key', true);
    
    IF edge_function_url IS NULL OR service_role_key IS NULL THEN
      RETURN NEW;
    END IF;

    payload := jsonb_build_object(
      'job_id',      NEW.id,
      'customer_id', NEW.customer_id,
      'old_status',  OLD.status,
      'new_status',  NEW.status
    );

    BEGIN
      SELECT net.http_post(
        url     := edge_function_url::text,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || service_role_key
        )::jsonb,
        body    := payload::jsonb
      ) INTO request_id;
    EXCEPTION WHEN others THEN
      -- Webhook failure must never block the job update
      RAISE WARNING 'handle_job_status_change: webhook error (non-fatal): %', SQLERRM;
    END;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
