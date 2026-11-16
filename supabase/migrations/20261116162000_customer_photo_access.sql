-- The customer could not open the photos of their own vehicle.
--
-- repair_photos had an INSERT policy only, so the tracking screen's query
-- returned nothing at all, and r2-presign's read rule allowed the ops prefix
-- to partner members only — the customer was not one. Both halves are fixed
-- here: the customer may now read the photo rows of their own jobs, and
-- customer_owns_job lets the function hand out a signed URL for the progress
-- photos of a job the caller owns.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'repair_photos'
      AND policyname = 'Customers can view photos of their own jobs'
  ) THEN
    CREATE POLICY "Customers can view photos of their own jobs"
      ON public.repair_photos
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.repair_jobs j
          WHERE j.id = repair_photos.job_id
            AND j.customer_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'repair_photos'
      AND policyname = 'Admins can view all repair photos'
  ) THEN
    CREATE POLICY "Admins can view all repair photos"
      ON public.repair_photos
      FOR SELECT
      USING (public.is_master_admin());
  END IF;
END;
$$;

-- Ownership check used by the r2-presign read rule. SECURITY DEFINER because
-- the caller's own RLS may not let it see the job row it is asking about.
CREATE OR REPLACE FUNCTION public.customer_owns_job(p_job_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_job_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.repair_jobs j
    WHERE j.id = p_job_id
      AND j.customer_id = v_uid
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.customer_owns_job(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_owns_job(uuid) TO authenticated;
