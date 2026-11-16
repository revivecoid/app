-- Receiving the car without a condition photo.
--
-- The owner of a workshop could admit a vehicle with a bare status change: no
-- shot of the car as it arrived. The customer is later shown the repair
-- photos, so a scratch that appeared in between had no evidence at all.
--
-- The staff app already asked for a photo; the owner's button did not. This
-- makes the database the single place that decides, so no surface can skip it.

CREATE OR REPLACE FUNCTION public.guard_repair_finished_needs_photo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contexts text[];
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- System moves (settlement, cron) are not a workshop claiming the work.
  IF current_setting('app.actor', true) = 'system' THEN
    RETURN NEW;
  END IF;

  -- An admin may move the job anyway, with a reason, and it is audited.
  IF public.is_master_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.status = '7_finished' THEN
    -- Proof that the work was done.
    v_contexts := ARRAY['in_progress', 'progress', 'finished', 'admitted'];
  ELSIF NEW.status = '5_admitted' THEN
    -- Proof of the car's condition when it arrived. The customer's own damage
    -- photos do not count: they were taken before the car reached the shop.
    v_contexts := ARRAY['booked', 'admitted', 'intake', 'vehicle_intake'];
  ELSE
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.repair_photos rp
     WHERE rp.job_id = NEW.id
       AND rp.step_context = ANY (v_contexts)
  ) THEN
    IF NEW.status = '7_finished' THEN
      RAISE EXCEPTION
        'PHOTO_REQUIRED: unggah minimal satu foto pengerjaan sebelum menandai pekerjaan selesai'
        USING ERRCODE = 'check_violation';
    END IF;
    RAISE EXCEPTION
      'PHOTO_REQUIRED: ambil foto kondisi kendaraan sebelum menerima kendaraan'
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
