-- Enable the pg_net extension to make HTTP requests from the database
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  payload JSONB;
  request_id BIGINT;
BEGIN
  -- Only trigger if the status has actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    
    -- IMPORTANT: Replace these with your actual Supabase Project URL and Service Role Key
    -- You can find these in your Supabase Dashboard -> Project Settings -> API
    edge_function_url := 'https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/send-notification';
    service_role_key := '<YOUR_SERVICE_ROLE_KEY>';

    -- Construct the exact JSON payload the edge function expects
    payload := jsonb_build_object(
      'job_id', NEW.id,
      'customer_id', NEW.customer_id,
      'old_status', OLD.status,
      'new_status', NEW.status
    );

    -- Fire the request asynchronously using pg_net
    SELECT
      net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_role_key
        ),
        body := payload
      ) INTO request_id;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger to watch the repair_jobs table
DROP TRIGGER IF EXISTS on_repair_job_status_change ON public.repair_jobs;
CREATE TRIGGER on_repair_job_status_change
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_job_status_change();
