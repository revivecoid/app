-- Migration: Remove pg_net HTTP call from notification trigger to prevent crashes

CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only trigger if the status has actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    
    -- Insert into local notifications table ONLY
    -- We are removing the net.http_post edge function call because it causes database crashes
    INSERT INTO public.notifications (user_id, title, message, type, related_id)
    VALUES (
      NEW.customer_id,
      'Status Updated',
      'Your vehicle is now ' || REPLACE(NEW.status, '_', ' '),
      'status_update',
      NEW.id
    );

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the old triggers are dropped
DROP TRIGGER IF EXISTS on_repair_job_status_change ON public.repair_jobs;
CREATE TRIGGER on_repair_job_status_change
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_job_status_change();
