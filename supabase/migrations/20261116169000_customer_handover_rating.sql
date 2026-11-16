-- The customer could never confirm the handover or rate the workshop.
--
-- Finding 12 of the 16 Nov 2026 review: the order finished at
-- 8_awaiting_delivery and the job closed without the owner's word, so CSAT
-- (C7) had no source at all and a workshop that never handed the car over
-- looked identical to one that did.

-- ── the customer's own record of the handover ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.job_handover_confirmations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      uuid NOT NULL UNIQUE REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating      smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  confirmed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.job_ratings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      uuid NOT NULL REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id  uuid REFERENCES public.partners(id) ON DELETE SET NULL,
  rating      smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_job_ratings_partner
  ON public.job_ratings (partner_id, created_at DESC);

ALTER TABLE public.job_handover_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers read own handover confirmations"
  ON public.job_handover_confirmations;
CREATE POLICY "Customers read own handover confirmations"
  ON public.job_handover_confirmations
  FOR SELECT
  USING (customer_id = auth.uid() OR public.is_master_admin());

DROP POLICY IF EXISTS "Customers read own ratings"
  ON public.job_ratings;
CREATE POLICY "Customers read own ratings"
  ON public.job_ratings
  FOR SELECT
  USING (customer_id = auth.uid() OR public.is_master_admin());

DROP POLICY IF EXISTS "Admins read all ratings"
  ON public.job_ratings;
CREATE POLICY "Admins read all ratings"
  ON public.job_ratings
  FOR SELECT
  USING (public.is_master_admin());

-- ── the one call the customer makes ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_confirm_handover(
  p_job_id uuid,
  p_rating smallint,
  p_comment text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job     RECORD;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Silakan masuk terlebih dahulu.');
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rating harus antara 1 dan 5.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order tidak ditemukan.');
  END IF;

  IF v_job.customer_id IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order ini bukan milik Anda.');
  END IF;

  -- The car has to be ready for pickup. Until then there is nothing to
  -- confirm and a rating would be a rating of nothing.
  IF v_job.status NOT IN ('8_awaiting_delivery', '9_done') THEN
    RETURN jsonb_build_object('success', false, 'error', format(
      'Mobil belum siap diambil. Status order: %s', v_job.status));
  END IF;

  INSERT INTO public.job_handover_confirmations
    (job_id, customer_id, rating, comment)
  VALUES (p_job_id, v_user_id, p_rating, NULLIF(btrim(COALESCE(p_comment, '')), ''))
  ON CONFLICT (job_id) DO UPDATE
    SET rating = EXCLUDED.rating,
        comment = EXCLUDED.comment,
        confirmed_at = now();

  INSERT INTO public.job_ratings
    (job_id, customer_id, partner_id, rating, comment)
  VALUES (p_job_id, v_user_id, v_job.partner_id, p_rating,
          NULLIF(btrim(COALESCE(p_comment, '')), ''))
  ON CONFLICT (job_id, customer_id) DO UPDATE
    SET rating = EXCLUDED.rating,
        comment = EXCLUDED.comment,
        partner_id = EXCLUDED.partner_id;

  -- Confirming the handover is what closes the order.
  IF v_job.status = '8_awaiting_delivery' THEN
    UPDATE public.repair_jobs
       SET status = '9_done',
           status_changed_at = now()
     WHERE id = p_job_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'job_id', p_job_id,
    'rating', p_rating,
    'new_status', '9_done');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_confirm_handover(uuid, smallint, text) TO authenticated;
