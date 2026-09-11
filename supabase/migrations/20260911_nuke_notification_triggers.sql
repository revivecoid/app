-- Migration: Nuke all notification functions and triggers

-- Drop the functions CASCADE, which will also drop any triggers attached to them!
DROP FUNCTION IF EXISTS public.notify_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.handle_job_status_change() CASCADE;

-- Now recreate only what we need (without net.http_post)
CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only trigger if the status has actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    
    -- Insert into local notifications table ONLY
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

CREATE TRIGGER on_repair_job_status_change
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_job_status_change();
