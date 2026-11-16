-- A workshop could finish a job without a single photo of the work.
--
-- The customer is promised photos of the repair, and the tracking screen shows
-- them, so a job that reaches 7_finished with an empty gallery is a job nobody
-- can check. This is enforced with a BEFORE UPDATE trigger rather than by
-- republishing transition_job, so the existing state machine (which is large and
-- already correct about who may go where) stays exactly as it is.
--
-- A master admin is not blocked: the admin already has to state a reason for an
-- override, and that reason is written to admin_audit_log.

CREATE OR REPLACE FUNCTION public.guard_repair_finished_needs_photo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- Only the "work is done" edge. Everything else keeps its own rules.
  IF NEW.status <> '7_finished' THEN
    RETURN NEW;
  END IF;

  -- System moves (settlement, cron) are not a workshop claiming the work.
  IF current_setting('app.actor', true) = 'system' THEN
    RETURN NEW;
  END IF;

  -- An admin may finish a job anyway, with a reason, and it is audited.
  IF public.is_master_admin() THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.repair_photos rp
     WHERE rp.job_id = NEW.id
       AND rp.step_context IN ('in_progress', 'progress', 'finished', 'admitted')
  ) THEN
    RAISE EXCEPTION
      'PHOTO_REQUIRED: unggah minimal satu foto pengerjaan sebelum menandai pekerjaan selesai'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_repair_finished_needs_photo ON public.repair_jobs;
CREATE TRIGGER trg_guard_repair_finished_needs_photo
  BEFORE UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_repair_finished_needs_photo();
