-- =============================================================================
-- 20260928090000_f9_estimation.sql
-- Fase 9: estimasi server-side, ai_usage, create_job_from_estimation,
--         vehicles upsert, claim_guest_estimations
-- Mengatasi: B-08, B-11, B-12, C-62, DAT-08, SEC-03(B-09)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: estimations table (B-11)
-- Hasil estimasi AI disimpan server, klien hanya pegang estimation_id
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.estimations (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  claim_token   text        UNIQUE,           -- untuk klaim tamu (B-12)
  status        text        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','success','failed')),
  model         text,
  panels        jsonb       NOT NULL DEFAULT '[]',
  total         bigint      NOT NULL DEFAULT 0,
  raw           jsonb,
  photo_keys    text[]      NOT NULL DEFAULT '{}',
  expires_at    timestamptz NOT NULL DEFAULT now() + INTERVAL '7 days',
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_estimations_user_id  ON public.estimations(user_id);
CREATE INDEX IF NOT EXISTS idx_estimations_token    ON public.estimations(claim_token) WHERE claim_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_estimations_expires  ON public.estimations(expires_at);

ALTER TABLE public.estimations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own estimations"    ON public.estimations;
DROP POLICY IF EXISTS "Service role manages estimations" ON public.estimations;
CREATE POLICY "Users read own estimations" ON public.estimations
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_master_admin());
CREATE POLICY "Service role manages estimations" ON public.estimations
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: ai_usage table (B-09, SEC-03)
-- Rate limit berbasis DB, per user per hari
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.ai_usage (
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day        date        NOT NULL DEFAULT CURRENT_DATE,
  count      int         NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_user_day ON public.ai_usage(user_id, day);

-- RPC: check and increment rate limit (called by Edge Function via service role)
CREATE OR REPLACE FUNCTION public.check_ai_rate_limit(
  p_user_id    uuid,
  p_is_anon    boolean DEFAULT false
)
RETURNS boolean  -- true = allowed, false = blocked
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit  int;
  v_count  int;
BEGIN
  -- Anon: 3/day; authed: from app_settings (default 20/day)
  IF p_is_anon THEN
    v_limit := 3;
  ELSE
    SELECT COALESCE((value::text)::int, 20) INTO v_limit
    FROM public.app_settings WHERE key = 'ai_daily_limit';
    v_limit := COALESCE(v_limit, 20);
  END IF;

  INSERT INTO public.ai_usage (user_id, day, count)
  VALUES (p_user_id, CURRENT_DATE, 1)
  ON CONFLICT (user_id, day) DO UPDATE
    SET count = ai_usage.count + 1
  RETURNING count INTO v_count;

  IF v_count > v_limit THEN
    -- Roll back the increment
    UPDATE public.ai_usage SET count = count - 1
    WHERE user_id = p_user_id AND day = CURRENT_DATE;
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_ai_rate_limit(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.check_ai_rate_limit(uuid, boolean) TO service_role, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: create_job_from_estimation RPC (B-11)
-- Klien hanya memanggil ini — tidak menulis langsung ke repair_jobs
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_job_from_estimation(
  p_estimation_id   uuid,
  p_vehicle_make    text,
  p_vehicle_model   text,
  p_vehicle_year    int,
  p_license_plate   text,
  p_contact_phone   text DEFAULT NULL,
  p_service_area    text DEFAULT NULL
)
RETURNS uuid  -- job_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_est       public.estimations;
  v_vehicle   RECORD;
  v_job_id    uuid;
  v_norm_plate text;
BEGIN
  -- Wajib login teridentifikasi
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Login required'; END IF;

  -- Load estimasi
  SELECT * INTO v_est FROM public.estimations WHERE id = p_estimation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ESTIMATION_ERROR: Not found'; END IF;
  IF v_est.status <> 'success' THEN
    RAISE EXCEPTION 'ESTIMATION_ERROR: Estimation status is %, must be success', v_est.status;
  END IF;
  IF v_est.expires_at < now() THEN
    RAISE EXCEPTION 'ESTIMATION_ERROR: Estimation expired';
  END IF;
  IF v_est.total <= 0 THEN
    RAISE EXCEPTION 'ESTIMATION_ERROR: Estimation has zero cost — at least one panel required';
  END IF;
  -- Estimasi harus milik caller atau tamu yang diklaim
  IF v_est.user_id IS NOT NULL AND v_est.user_id <> v_user_id THEN
    RAISE EXCEPTION 'ESTIMATION_ERROR: Not your estimation';
  END IF;

  -- B-08/DAT-08 fix: upsert kendaraan per (customer_id, normalized_plate)
  v_norm_plate := CASE
    WHEN p_license_plate IS NULL OR trim(p_license_plate) = '' THEN NULL
    ELSE upper(regexp_replace(trim(p_license_plate), '[^A-Z0-9]', '', 'g'))
  END;

  INSERT INTO public.vehicles (customer_id, make, model, year, license_plate)
  VALUES (v_user_id, trim(p_vehicle_make), trim(p_vehicle_model), p_vehicle_year, v_norm_plate)
  ON CONFLICT (customer_id, license_plate) DO UPDATE
    SET make = EXCLUDED.make, model = EXCLUDED.model, year = EXCLUDED.year, updated_at = now()
  RETURNING * INTO v_vehicle;

  -- Buat job dari estimasi (price dari server, bukan klien — B-11)
  INSERT INTO public.repair_jobs (
    customer_id, vehicle_id,
    initial_estimation_cost, estimation_result,
    status, service_area, contact_phone
  )
  VALUES (
    v_user_id, v_vehicle.id,
    v_est.total,
    jsonb_build_object(
      'estimation_id', v_est.id,
      'panels', v_est.panels,
      'model', v_est.model,
      'photo_keys', v_est.photo_keys
    ),
    '2_estimated',
    p_service_area,
    normalize_id_phone(p_contact_phone)
  )
  RETURNING id INTO v_job_id;

  -- Link foto ke repair_photos (C-35)
  INSERT INTO public.repair_photos (job_id, file_key, step_context, uploaded_by)
  SELECT v_job_id, unnest(v_est.photo_keys), 'estimate', v_user_id
  ON CONFLICT DO NOTHING;

  -- Tandai estimasi sudah dipakai
  UPDATE public.estimations SET expires_at = now() WHERE id = p_estimation_id;

  RETURN v_job_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_job_from_estimation(uuid,text,text,int,text,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_job_from_estimation(uuid,text,text,int,text,text,text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: claim_guest_estimations (B-12, C-62)
-- Pindahkan estimasi dan job dari uid tamu ke akun yang login
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.claim_guest_jobs(text);
DROP FUNCTION IF EXISTS public.claim_guest_estimations(text[], text);

CREATE OR REPLACE FUNCTION public.claim_guest_estimations(
  p_estimation_ids  uuid[],
  p_claim_token     text
)
RETURNS int  -- jumlah yang berhasil diklaim
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_claimed  int := 0;
  v_est_id   uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  FOREACH v_est_id IN ARRAY p_estimation_ids LOOP
    -- Klaim hanya bila token cocok (bukti kepemilikan sesi tamu)
    UPDATE public.estimations
    SET user_id = v_user_id, claim_token = NULL
    WHERE id = v_est_id
      AND claim_token = p_claim_token
      AND (user_id IS NULL OR user_id <> v_user_id);

    IF FOUND THEN
      v_claimed := v_claimed + 1;
      -- Klaim job yang terkait
      UPDATE public.repair_jobs
      SET customer_id = v_user_id
      WHERE estimation_result->>'estimation_id' = v_est_id::text
        AND customer_id <> v_user_id;
    END IF;
  END LOOP;

  RETURN v_claimed;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_guest_estimations(uuid[], text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_guest_estimations(uuid[], text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: vehicles unique constraint (B-08, DAT-08)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema='public' AND table_name='vehicles'
      AND constraint_name='vehicles_customer_plate_unique'
  ) THEN
    ALTER TABLE public.vehicles
      ADD CONSTRAINT vehicles_customer_plate_unique
        UNIQUE (customer_id, license_plate);
  END IF;
EXCEPTION WHEN others THEN NULL;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: app_settings — ai_daily_limit default
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.app_settings (key, value)
VALUES ('ai_daily_limit', '20')
ON CONFLICT (key) DO NOTHING;

-- Cron: bersihkan estimasi kedaluwarsa dan akun anonim lama
-- (Jadwalkan manual di Supabase — lihat MANUAL.md)

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFIKASI
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema='public' AND table_name IN ('estimations','ai_usage')
-- ORDER BY table_name;
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname IN ('check_ai_rate_limit','create_job_from_estimation','claim_guest_estimations')
-- ORDER BY proname;
