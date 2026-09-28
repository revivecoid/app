-- =============================================================================
-- 20260928070000_f7_booking_capacity.sql
-- Fase 7: model kapasitas tunggal, hari libur, area layanan
-- Mengatasi: S-03, BIZ-05, BIZ-06, C-10, C-41, C-68, L-07, L-09, REL-14, REL-16, S-10
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: service_areas (S-10) — satu sumber untuk area layanan
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.service_areas (
  code   text PRIMARY KEY,
  label  text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

INSERT INTO public.service_areas (code, label) VALUES
  ('jakarta_selatan',  'Jakarta Selatan'),
  ('jakarta_utara',    'Jakarta Utara'),
  ('jakarta_barat',    'Jakarta Barat'),
  ('jakarta_timur',    'Jakarta Timur'),
  ('jakarta_pusat',    'Jakarta Pusat'),
  ('tangerang',        'Tangerang'),
  ('tangerang_selatan','Tangerang Selatan'),
  ('bekasi',           'Bekasi'),
  ('depok',            'Depok'),
  ('bogor',            'Bogor'),
  ('bandung',          'Bandung'),
  ('surabaya',         'Surabaya'),
  ('other',            'Lainnya')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.service_areas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated reads service_areas" ON public.service_areas;
CREATE POLICY "Authenticated reads service_areas" ON public.service_areas
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admin manages service_areas" ON public.service_areas;
CREATE POLICY "Admin manages service_areas" ON public.service_areas
  FOR ALL TO authenticated USING (is_master_admin()) WITH CHECK (is_master_admin());

-- Pastikan kolom service_area di partners bertipe text (bukan ENUM)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='partners' AND column_name='service_area'
  ) THEN
    ALTER TABLE public.partners ADD COLUMN service_area text REFERENCES public.service_areas(code);
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: holidays (C-41, C-68, REL-16) — satu tabel hari libur
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.holidays (
  date   date PRIMARY KEY,
  name   text NOT NULL,
  source text NOT NULL DEFAULT 'sync-holidays'
);

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated reads holidays" ON public.holidays;
CREATE POLICY "Authenticated reads holidays" ON public.holidays
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Service role manages holidays" ON public.holidays;
CREATE POLICY "Service role manages holidays" ON public.holidays
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Index untuk range query
CREATE INDEX IF NOT EXISTS idx_holidays_date ON public.holidays(date);

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: partner_day_capacity (S-03, BIZ-05)
-- View/fungsi tunggal untuk kapasitas harian bengkel
-- ─────────────────────────────────────────────────────────────────────────────

-- Hapus jika sudah ada versi lama
DROP FUNCTION IF EXISTS public.partner_day_capacity(uuid, date);

CREATE OR REPLACE FUNCTION public.partner_day_capacity(
  p_partner_id uuid,
  p_date       date
)
RETURNS TABLE (capacity int, used int, available int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_capacity int;
  v_used     int;
BEGIN
  -- Prioritas kapasitas: override harian > jadwal mingguan > default 5
  SELECT
    COALESCE(
      (SELECT slots FROM public.partner_capacity_overrides
       WHERE partner_id = p_partner_id AND date = p_date),
      (SELECT guaranteed_slots_per_day FROM public.partner_schedules
       WHERE partner_id = p_partner_id
         AND (standard_working_days IS NULL
              OR (p_date - '2001-01-01') % 7 = ANY(
                   (SELECT array_agg((unnest::integer - 1) % 7)
                    FROM unnest(
                      CASE WHEN jsonb_typeof(standard_working_days::jsonb) = 'array'
                           THEN ARRAY(SELECT jsonb_array_elements_text(standard_working_days::jsonb))::integer[]
                           ELSE ARRAY[1,2,3,4,5,6]
                      END
                    ) AS t
                   )
                 )
         )
       LIMIT 1),
      5  -- default bila belum ada jadwal
    ) INTO v_capacity;

  -- Used = job aktif (counts_for_capacity) di hari itu
  -- L-07 fix: TIDAK menghitung 0_cancelled
  SELECT COUNT(*)::int INTO v_used
  FROM public.repair_jobs r
  JOIN public.job_statuses js ON js.code = r.status
  WHERE r.partner_id = p_partner_id
    AND r.scheduled_date::date = p_date
    AND js.counts_for_capacity = true;

  RETURN QUERY SELECT v_capacity, v_used, GREATEST(0, v_capacity - v_used);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.partner_day_capacity(uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.partner_day_capacity(uuid, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: partner_capacity_overrides (bila belum ada)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.partner_capacity_overrides (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  date       date NOT NULL,
  slots      int  NOT NULL CHECK (slots >= 0 AND slots <= 50),
  note       text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, date)
);

CREATE INDEX IF NOT EXISTS idx_cap_overrides_partner_date
  ON public.partner_capacity_overrides(partner_id, date);

ALTER TABLE public.partner_capacity_overrides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Owner manages capacity overrides" ON public.partner_capacity_overrides;
CREATE POLICY "Owner manages capacity overrides" ON public.partner_capacity_overrides
  FOR ALL TO authenticated
  USING (has_partner_membership(partner_id, ARRAY['owner']::public.membership_role[]) OR is_master_admin())
  WITH CHECK (has_partner_membership(partner_id, ARRAY['owner']::public.membership_role[]) OR is_master_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: get_available_dates (S-03, C-41, BIZ-05)
-- RPC untuk kalender booking: hitung di server, bukan klien
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_available_dates(uuid, date, date);

CREATE OR REPLACE FUNCTION public.get_available_dates(
  p_partner_id uuid,
  p_from       date DEFAULT CURRENT_DATE,
  p_to         date DEFAULT CURRENT_DATE + 60
)
RETURNS TABLE (
  date            date,
  capacity        int,
  used            int,
  available       int,
  is_working_day  boolean,
  is_holiday      boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_d        date;
  v_sched    RECORD;
  v_wdays    int[];
BEGIN
  -- Baca jadwal partner untuk working days
  SELECT standard_working_days INTO v_sched
  FROM public.partner_schedules WHERE partner_id = p_partner_id LIMIT 1;

  -- Default: Senin–Sabtu (1–6)
  v_wdays := COALESCE(
    CASE WHEN v_sched.standard_working_days IS NOT NULL
         THEN ARRAY(SELECT jsonb_array_elements_text(v_sched.standard_working_days::jsonb))::int[]
    END,
    ARRAY[1,2,3,4,5,6]
  );

  v_d := p_from;
  WHILE v_d <= p_to LOOP
    DECLARE
      v_cap       int;
      v_used_cnt  int;
      v_avail     int;
      v_is_work   boolean;
      v_is_hol    boolean;
    BEGIN
      -- Apakah hari kerja?
      v_is_work := (EXTRACT(isodow FROM v_d)::int) = ANY(v_wdays);
      -- Apakah hari libur?
      SELECT EXISTS(SELECT 1 FROM public.holidays WHERE date = v_d) INTO v_is_hol;

      SELECT c.capacity, c.used, c.available
        INTO v_cap, v_used_cnt, v_avail
        FROM public.partner_day_capacity(p_partner_id, v_d) c;

      RETURN NEXT;
      date           := v_d;
      capacity       := v_cap;
      used           := v_used_cnt;
      available      := CASE WHEN v_is_work AND NOT v_is_hol THEN v_avail ELSE 0 END;
      is_working_day := v_is_work;
      is_holiday     := v_is_hol;
    END;
    v_d := v_d + 1;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_available_dates(uuid, date, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_available_dates(uuid, date, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: book_slot — tambahkan advisory lock + filter cancelled (BIZ-05, L-07)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.book_slot(
  p_job_id     uuid,
  p_partner_id uuid,
  p_date       date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_avail   int;
  v_job     public.repair_jobs;
BEGIN
  -- BIZ-05: advisory lock per partner+date untuk mencegah race
  PERFORM pg_advisory_xact_lock(hashtext(p_partner_id::text || p_date::text));

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BOOK_ERROR: Job not found'; END IF;
  IF v_job.status NOT IN ('2_estimated') THEN
    RAISE EXCEPTION 'BOOK_ERROR: Job status must be 2_estimated, got %', v_job.status;
  END IF;

  -- C-41: tolak hari libur
  IF EXISTS (SELECT 1 FROM public.holidays WHERE date = p_date) THEN
    RAISE EXCEPTION 'BOOK_ERROR: Date % is a public holiday', p_date;
  END IF;

  -- Cek kapasitas di server (L-07: sudah exclude 0_cancelled)
  SELECT c.available INTO v_avail
  FROM public.partner_day_capacity(p_partner_id, p_date) c;

  IF v_avail <= 0 THEN
    RAISE EXCEPTION 'BOOK_ERROR: No capacity available for partner % on %', p_partner_id, p_date;
  END IF;

  -- Perbarui job
  UPDATE public.repair_jobs
  SET partner_id     = p_partner_id,
      scheduled_date = p_date,
      updated_at     = now()
  WHERE id = p_job_id;

  -- Transisi status 2_estimated → 3_booked via transition_job
  PERFORM set_config('app.actor', 'system', true);
  PERFORM public.transition_job(p_job_id, '3_booked', '2_estimated',
    'book_slot:' || p_partner_id, '{}');
  PERFORM set_config('app.actor', '', true);

  -- L-07: partner_booked_slots tidak dipakai — jadikan no-op (tabel ada tapi tidak dibaca)
  -- Dibersihkan oleh transition_job saat cancelled melalui trigger
END;
$$;

REVOKE EXECUTE ON FUNCTION public.book_slot(uuid, uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.book_slot(uuid, uuid, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: Trigger — kosongkan scheduled_date saat 0_cancelled (L-07)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.on_job_cancelled_clear_slot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = '0_cancelled' AND OLD.status <> '0_cancelled' THEN
    NEW.scheduled_date := NULL;
    NEW.partner_id     := NULL;  -- lepas dari bengkel
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS job_cancelled_clear_slot ON public.repair_jobs;
CREATE TRIGGER job_cancelled_clear_slot
  BEFORE UPDATE OF status ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.on_job_cancelled_clear_slot();

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 8: execute_auto_assign — fix L-09 (service_area fallback)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.execute_auto_assign(p_job_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job         public.repair_jobs;
  v_settings    public.auto_assign_settings;
  v_partner     RECORD;
  v_target_date date;
  v_partner_id  uuid;
  v_log_note    text := '';
BEGIN
  -- Ambil job
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Job not found'; END IF;
  IF v_job.customer_id <> auth.uid() THEN
    RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Only job owner can trigger auto-assign';
  END IF;
  IF v_job.status <> '2_estimated' THEN
    RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Job must be 2_estimated, got %', v_job.status;
  END IF;

  -- Ambil pengaturan auto-assign
  SELECT * INTO v_settings FROM public.auto_assign_settings LIMIT 1;

  v_target_date := COALESCE(v_job.scheduled_date::date, CURRENT_DATE + 1);

  -- L-09 fix: coba cocokkan lokasi dulu, FALLBACK ke semua aktif bila kosong
  SELECT p.id INTO v_partner_id
  FROM public.partners p
  JOIN public.memberships m ON m.org_id = p.id AND m.role = 'owner' AND m.status = 'active'
  WHERE p.is_active = true
    AND p.status = 'approved'
    AND (
      -- Cocokkan lokasi bila diaktifkan dan job punya service_area
      NOT COALESCE(v_settings.match_location, false)
      OR v_job.service_area IS NULL
      OR p.service_area IS NULL
      OR p.service_area = v_job.service_area
    )
    AND (
      SELECT available FROM public.partner_day_capacity(p.id, v_target_date)
    ) > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.holidays WHERE date = v_target_date
    )
  ORDER BY (
    SELECT used FROM public.partner_day_capacity(p.id, v_target_date)
  ) ASC
  LIMIT 1;

  -- Bila match_location aktif tapi tidak ada hasil, log fallback
  IF v_partner_id IS NULL AND COALESCE(v_settings.match_location, false)
     AND v_job.service_area IS NOT NULL THEN
    v_log_note := 'location_match_fallback: no partner in area ' || v_job.service_area;
    -- Fallback: cari tanpa filter lokasi
    SELECT p.id INTO v_partner_id
    FROM public.partners p
    JOIN public.memberships m ON m.org_id = p.id AND m.role = 'owner' AND m.status = 'active'
    WHERE p.is_active = true AND p.status = 'approved'
      AND (SELECT available FROM public.partner_day_capacity(p.id, v_target_date)) > 0
      AND NOT EXISTS (SELECT 1 FROM public.holidays WHERE date = v_target_date)
    ORDER BY (SELECT used FROM public.partner_day_capacity(p.id, v_target_date)) ASC
    LIMIT 1;
  END IF;

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: No eligible partner found for date %', v_target_date;
  END IF;

  -- Book slot (dengan advisory lock)
  PERFORM public.book_slot(p_job_id, v_partner_id, v_target_date);

  -- Catat fallback di audit log bila terjadi
  IF v_log_note <> '' THEN
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES ('AUTO_ASSIGN_FALLBACK', 'repair_jobs', p_job_id, auth.uid(),
      jsonb_build_object('note', v_log_note, 'assigned_partner', v_partner_id));
  END IF;

  RETURN v_partner_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.execute_auto_assign(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.execute_auto_assign(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 9: partner_update_capacity RPC (C-10) — jadwal + kapasitas via RPC
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.partner_update_capacity(
  p_working_days     int[],
  p_slots_per_day    int,
  p_blacklisted_dates date[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_partner_id uuid;
BEGIN
  v_partner_id := get_my_partner_id();
  IF v_partner_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Not a partner'; END IF;
  IF NOT has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only owner can update capacity settings';
  END IF;
  IF p_slots_per_day < 1 OR p_slots_per_day > 50 THEN
    RAISE EXCEPTION 'VALIDATION: slots_per_day must be 1-50, got %', p_slots_per_day;
  END IF;

  INSERT INTO public.partner_schedules (
    partner_id, guaranteed_slots_per_day, standard_working_days, blacklisted_dates
  )
  VALUES (
    v_partner_id,
    p_slots_per_day,
    to_jsonb(p_working_days),
    to_jsonb(p_blacklisted_dates)
  )
  ON CONFLICT (partner_id) DO UPDATE
    SET guaranteed_slots_per_day = EXCLUDED.guaranteed_slots_per_day,
        standard_working_days    = EXCLUDED.standard_working_days,
        blacklisted_dates        = EXCLUDED.blacklisted_dates,
        updated_at               = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.partner_update_capacity(int[], int, date[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.partner_update_capacity(int[], int, date[]) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFIKASI
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema='public'
--     AND table_name IN ('service_areas','holidays','partner_capacity_overrides')
-- ORDER BY table_name;
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname IN ('partner_day_capacity','get_available_dates','book_slot',
--                   'execute_auto_assign','partner_update_capacity',
--                   'on_job_cancelled_clear_slot')
-- ORDER BY proname;
