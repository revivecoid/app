-- Claim a job that was estimated anonymously.
--
-- A guest gets a real (anonymous) session so the vision pipeline can stay
-- authenticated, which means the guest OWNS the row it wrote: repair_jobs
-- INSERT requires auth.uid() = customer_id. If that visitor later signs in with
-- Google and the email matches an existing account, GoTrue cannot always merge
-- the anonymous row — it is left owned by an id nobody can log back into, so the
-- booking they were in the middle of disappears.
--
-- This lets the signer-in take those rows over, under strict limits:
--   * only an anonymous CURRENT user may call it (a guest taking over a job),
--   * the caller must now carry a real email, i.e. the conversion just happened,
--   * only rows owned by the calling user, unassigned, and still pre-payment.
-- A partial index keeps it cheap for the common case of no guest rows at all.

CREATE INDEX IF NOT EXISTS repair_jobs_guest_claim_idx
  ON public.repair_jobs (customer_id)
  WHERE partner_id IS NULL;

CREATE OR REPLACE FUNCTION public.claim_guest_jobs()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user   RECORD;
  v_count  INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_user FROM auth.users WHERE id = auth.uid();

  IF v_user IS NULL OR NOT COALESCE(v_user.is_anonymous, false) THEN
    RAISE EXCEPTION 'only an anonymous (guest) session may claim guest jobs'
      USING ERRCODE = '42501';
  END IF;

  IF v_user.email IS NULL OR v_user.email = '' THEN
    RAISE EXCEPTION 'no email on this account yet' USING ERRCODE = '42501';
  END IF;

  UPDATE public.repair_jobs
     SET customer_id = v_user.id,
         updated_at  = now()
   WHERE customer_id = v_user.id
     AND partner_id IS NULL
     AND status IN ('1_intake', '2_estimated');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_guest_jobs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_guest_jobs() TO authenticated;
