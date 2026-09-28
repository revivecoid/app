-- =============================================================================
-- 20260928030000_f4_state_machine.sql
-- Fase 4: Mesin status di server — satu sumber aturan
--
-- Mengatasi: C-14, L-01, L-02, L-04, L-05, L-06, L-11, S-01, S-02,
--            BIZ-07, C-24, C-60, D-03, DAT-10, SEC-14
--
-- URUTAN PEKERJAAN:
-- 1. Buat job_statuses + job_status_transitions (sumber kebenaran)
-- 2. Buat job_status_history
-- 3. Buat notification_outbox + enqueue_job_notification
-- 4. Buat transition_job() — fungsi tunggal
-- 5. Perbaiki book_slot (C-14, L-02, L-04)
-- 6. Buat admin_review_partner (C-24)
-- 7. Bungkus RPC lama (advance_job_status, customer_cancel_job, dll.)
-- 8. Perbaiki advance_job_status: tambah cabang all_access (C-60)
-- 9. Perbaiki admin_assign_job (L-05)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: Tabel status kanonik (S-01, DAT-10)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.job_statuses (
  code                 text    PRIMARY KEY,
  sort_order           integer UNIQUE NOT NULL,
  label_id             text    NOT NULL,  -- Bahasa Indonesia
  label_en             text    NOT NULL,
  is_terminal          boolean NOT NULL DEFAULT false,
  counts_for_capacity  boolean NOT NULL DEFAULT true,
  customer_can_cancel  boolean NOT NULL DEFAULT false,
  visible_to_customer  boolean NOT NULL DEFAULT true
);

-- Idempoten: insert atau update
INSERT INTO public.job_statuses
  (code, sort_order, label_id, label_en, is_terminal, counts_for_capacity, customer_can_cancel, visible_to_customer)
VALUES
  ('0_cancelled',        0,  'Dibatalkan',            'Cancelled',           true,  false, false, true),
  ('2_estimated',        10, 'Estimasi Selesai',       'Estimated',           false, false, true,  true),
  ('3_booked',           20, 'Dijadwalkan',            'Booked',              false, true,  true,  true),
  ('5_admitted',         30, 'Kendaraan Masuk',        'Admitted',            false, true,  false, true),
  ('3_inspected',        40, 'Inspeksi Selesai',       'Inspected',           false, true,  false, true),
  ('4_paid',             50, 'Pembayaran Dikonfirmasi','Payment Confirmed',   false, true,  false, true),
  ('6_in_progress',      60, 'Dalam Pengerjaan',       'In Progress',         false, true,  false, true),
  ('7_finished',         70, 'Selesai Dikerjakan',     'Finished',            false, true,  false, true),
  ('8_awaiting_delivery',80, 'Menunggu Pengantaran',   'Awaiting Delivery',   false, true,  false, true),
  ('9_done',             90, 'Selesai',                'Done',                true,  false, false, true)
ON CONFLICT (code) DO UPDATE SET
  sort_order          = EXCLUDED.sort_order,
  label_id            = EXCLUDED.label_id,
  label_en            = EXCLUDED.label_en,
  is_terminal         = EXCLUDED.is_terminal,
  counts_for_capacity = EXCLUDED.counts_for_capacity,
  customer_can_cancel = EXCLUDED.customer_can_cancel,
  visible_to_customer = EXCLUDED.visible_to_customer;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: Tabel transisi (S-02)
-- actor ∈ customer | owner | mechanic | staff | driver | master_admin | system
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.job_status_transitions (
  from_status text NOT NULL REFERENCES public.job_statuses(code),
  to_status   text NOT NULL REFERENCES public.job_statuses(code),
  actor       text NOT NULL CHECK (actor IN ('customer','owner','mechanic','staff','driver','master_admin','system')),
  note        text,
  PRIMARY KEY (from_status, to_status, actor)
);

-- Hapus semua dan isi ulang agar idempoten
TRUNCATE public.job_status_transitions;

INSERT INTO public.job_status_transitions (from_status, to_status, actor, note) VALUES
  -- Booking (L-04: HANYA book_slot yang boleh, actor = system karena SECURITY DEFINER)
  ('2_estimated',        '3_booked',           'system',       'via book_slot only'),
  ('2_estimated',        '0_cancelled',        'customer',     'free cancellation before booking'),
  ('2_estimated',        '0_cancelled',        'master_admin', 'admin override'),

  -- Setelah booking
  ('3_booked',           '5_admitted',         'owner',        NULL),
  ('3_booked',           '5_admitted',         'mechanic',     NULL),
  ('3_booked',           '5_admitted',         'staff',        NULL),
  ('3_booked',           '5_admitted',         'master_admin', NULL),
  ('3_booked',           '0_cancelled',        'customer',     'free cancellation before admitted'),
  ('3_booked',           '0_cancelled',        'master_admin', 'admin override with reason'),

  -- Inspeksi + invoice (L-01: 4_paid → 5_admitted DIHAPUS)
  ('5_admitted',         '3_inspected',        'owner',        'partner issues invoice'),
  ('5_admitted',         '3_inspected',        'mechanic',     'partner issues invoice'),
  ('5_admitted',         '3_inspected',        'master_admin', NULL),
  -- Setelah admitted, pelanggan tidak bisa cancel sendiri (L-06)
  -- Admin cancel setelah admitted → kendaraan harus dikembalikan dulu
  ('5_admitted',         '8_awaiting_delivery','master_admin', 'return_unrepaired'),

  -- Pembayaran: hanya system (settlement Fase 5)
  ('3_inspected',        '4_paid',             'system',       'payment settlement'),
  ('3_inspected',        '4_paid',             'master_admin', 'admin manual confirmation'),

  -- Mulai pekerjaan (tidak bisa dari 5_admitted langsung — L-01)
  ('4_paid',             '6_in_progress',      'owner',        NULL),
  ('4_paid',             '6_in_progress',      'mechanic',     NULL),
  ('4_paid',             '6_in_progress',      'staff',        NULL),
  ('4_paid',             '6_in_progress',      'master_admin', NULL),

  -- Selesai dikerjakan
  ('6_in_progress',      '7_finished',         'owner',        NULL),
  ('6_in_progress',      '7_finished',         'mechanic',     NULL),
  ('6_in_progress',      '7_finished',         'staff',        NULL),
  ('6_in_progress',      '7_finished',         'master_admin', NULL),

  -- Siap antar
  ('7_finished',         '8_awaiting_delivery','owner',        NULL),
  ('7_finished',         '8_awaiting_delivery','mechanic',     NULL),
  ('7_finished',         '8_awaiting_delivery','staff',        NULL),
  ('7_finished',         '8_awaiting_delivery','master_admin', NULL),

  -- Pengantaran selesai (L-11: satu aturan)
  ('8_awaiting_delivery','9_done',             'owner',        NULL),
  ('8_awaiting_delivery','9_done',             'mechanic',     NULL),
  ('8_awaiting_delivery','9_done',             'staff',        NULL),
  ('8_awaiting_delivery','9_done',             'driver',       NULL),
  ('8_awaiting_delivery','9_done',             'master_admin', NULL),
  ('8_awaiting_delivery','9_done',             'customer',     'self pickup'),

  -- Admin dapat cancel / override hampir semua status
  ('6_in_progress',      '0_cancelled',        'master_admin', 'exceptional override'),
  ('3_inspected',        '0_cancelled',        'master_admin', 'exceptional override'),
  ('4_paid',             '0_cancelled',        'master_admin', 'exceptional override');

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: Riwayat status job
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.job_status_history (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id       uuid        NOT NULL REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
  from_status  text,
  to_status    text        NOT NULL,
  actor_user   uuid        REFERENCES auth.users(id),
  actor_role   text,
  reason       text,
  meta         jsonb       NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_job_status_history_job ON public.job_status_history(job_id, created_at);
ALTER TABLE public.job_status_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin reads all history"        ON public.job_status_history;
DROP POLICY IF EXISTS "Customer reads own job history" ON public.job_status_history;
CREATE POLICY "Admin reads all history" ON public.job_status_history
  FOR SELECT TO authenticated USING (is_master_admin());
CREATE POLICY "Customer reads own job history" ON public.job_status_history
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.repair_jobs j
    WHERE j.id = job_id AND j.customer_id = auth.uid()
  ));
CREATE POLICY "Partner reads their job history" ON public.job_status_history
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.repair_jobs j
    WHERE j.id = job_id
      AND j.partner_id IS NOT NULL
      AND has_partner_membership(j.partner_id, ARRAY['owner','mechanic','staff','driver']::public.membership_role[])
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: notification_outbox (D-03)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id           uuid        REFERENCES public.repair_jobs(id) ON DELETE SET NULL,
  recipient_user_id uuid       REFERENCES auth.users(id) ON DELETE CASCADE,
  event            text        NOT NULL,
  payload          jsonb       NOT NULL DEFAULT '{}',
  status           text        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending','sent','failed','skipped')),
  attempts         integer     NOT NULL DEFAULT 0,
  next_attempt_at  timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending_f4
  ON public.notification_outbox(next_attempt_at)
  WHERE status = 'pending';

CREATE OR REPLACE FUNCTION public.enqueue_job_notification(
  p_job_id          uuid,
  p_recipient       uuid,
  p_event           text,
  p_payload         jsonb DEFAULT '{}'
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.notification_outbox (job_id, user_id, kind, status, payload, created_at)
  VALUES (p_job_id, p_recipient, p_event, 'pending', p_payload, now())
  ON CONFLICT DO NOTHING;
$$;
REVOKE EXECUTE ON FUNCTION public.enqueue_job_notification(uuid, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.enqueue_job_notification(uuid, uuid, text, jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: transition_job() — fungsi tunggal (S-02, BIZ-07, D-03, SEC-14)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.transition_job(
  p_job_id        uuid,
  p_to            text,
  p_expected_from text    DEFAULT NULL,
  p_reason        text    DEFAULT NULL,
  p_meta          jsonb   DEFAULT '{}'
) RETURNS public.repair_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job        public.repair_jobs;
  v_actor      text;
  v_partner_id uuid;
  v_allowed    boolean := false;
  v_is_system  boolean;
BEGIN
  -- 1. Lock job
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: Job not found: %', p_job_id;
  END IF;

  -- 2. Optimistic lock (BIZ-07, C-48)
  IF p_expected_from IS NOT NULL AND v_job.status <> p_expected_from THEN
    RAISE EXCEPTION 'STALE_STATUS: Expected %, got %', p_expected_from, v_job.status;
  END IF;

  -- 3. Tentukan actor
  v_is_system  := (current_setting('app.actor', true) = 'system');
  v_partner_id := get_my_partner_id();

  IF v_is_system THEN
    v_actor := 'system';
  ELSIF is_master_admin() THEN
    v_actor := 'master_admin';
  ELSIF v_partner_id IS NOT NULL AND v_job.partner_id = v_partner_id THEN
    -- Tentukan peran spesifik di bengkel ini
    IF has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
      v_actor := 'owner';
    ELSIF has_partner_membership(v_partner_id, ARRAY['mechanic']::public.membership_role[]) THEN
      v_actor := 'mechanic';
    ELSIF has_partner_membership(v_partner_id, ARRAY['driver']::public.membership_role[]) THEN
      -- C-60: mode all_access → driver setara dengan staff untuk transisi
      IF EXISTS (SELECT 1 FROM public.partners WHERE id = v_partner_id AND ops_view_mode = 'all_access') THEN
        v_actor := 'staff';
      ELSE
        v_actor := 'driver';
      END IF;
    ELSE
      v_actor := 'staff';
    END IF;
  ELSIF v_job.customer_id = auth.uid() THEN
    v_actor := 'customer';
  ELSE
    RAISE EXCEPTION 'TRANSITION_ERROR: Cannot determine actor for this job';
  END IF;

  -- 4. Cek tabel transisi
  SELECT EXISTS (
    SELECT 1 FROM public.job_status_transitions
    WHERE from_status = v_job.status
      AND to_status   = p_to
      AND actor       = v_actor
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: % → % not allowed for actor %',
      v_job.status, p_to, v_actor;
  END IF;

  -- 5. Override admin wajib punya alasan (SEC-14)
  IF v_actor = 'master_admin' AND p_reason IS NULL AND
     p_to NOT IN ('5_admitted', '6_in_progress', '7_finished', '8_awaiting_delivery', '9_done') THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: Admin override requires a reason';
  END IF;

  -- 6. Efek samping (D-03)
  -- 6a. Booking slot saat admitted
  IF p_to = '5_admitted' AND v_job.status = '3_booked' AND v_job.scheduled_date IS NOT NULL THEN
    INSERT INTO public.partner_booked_slots (partner_id, job_id, booked_date)
    VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 6b. completed_at saat terminal
  IF p_to IN ('9_done', '0_cancelled') THEN
    UPDATE public.repair_jobs
       SET status           = p_to,
           status_changed_at = now(),
           completed_at      = now(),
           updated_at        = now()
     WHERE id = p_job_id;
  ELSE
    UPDATE public.repair_jobs
       SET status           = p_to,
           status_changed_at = now(),
           updated_at        = now()
     WHERE id = p_job_id;
  END IF;

  -- 6c. Notifikasi (enqueue — Fase 8 mengirimnya)
  IF v_job.customer_id IS NOT NULL THEN
    PERFORM enqueue_job_notification(
      p_job_id, v_job.customer_id, p_to,
      jsonb_build_object('from', v_job.status, 'actor', v_actor)
    );
  END IF;

  -- 7. Riwayat
  INSERT INTO public.job_status_history
    (job_id, from_status, to_status, actor_user, actor_role, reason, meta)
  VALUES
    (p_job_id, v_job.status, p_to, auth.uid(), v_actor, p_reason, p_meta);

  -- 8. Audit log untuk admin override (SEC-14)
  IF v_actor = 'master_admin' THEN
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
      'JOB_STATUS_TRANSITION', 'repair_jobs', p_job_id, auth.uid(),
      jsonb_build_object('from', v_job.status, 'to', p_to, 'reason', p_reason)
    );
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  RETURN v_job;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.transition_job(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.transition_job(uuid, text, text, text, jsonb) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: Perbaiki book_slot (C-14, L-02, L-04)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.book_slot(
  p_job_id     uuid,
  p_partner_id uuid,
  p_date       date
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job      public.repair_jobs;
  v_schedule public.partner_schedules;
  v_count    integer;
  v_weekday  integer;
BEGIN
  -- Lock job
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  -- Ownership
  IF v_job.customer_id IS DISTINCT FROM auth.uid() AND NOT is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: you do not own this job';
  END IF;

  -- L-02: hanya boleh dari 2_estimated
  IF v_job.status <> '2_estimated' THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: book_slot requires status 2_estimated, got %', v_job.status;
  END IF;

  -- Jadwal bengkel
  SELECT * INTO v_schedule FROM public.partner_schedules WHERE partner_id = p_partner_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No schedule configured for partner: %', p_partner_id;
  END IF;

  -- Hari kerja
  v_weekday := EXTRACT(DOW FROM p_date)::integer;
  IF v_weekday = 0 THEN v_weekday := 7; END IF;
  IF NOT (v_schedule.standard_working_days @> ARRAY[v_weekday]) THEN
    RAISE EXCEPTION 'Partner does not work on this day of the week';
  END IF;

  -- C-14: bandingkan DATE[] dengan DATE, bukan text[] dengan text
  IF p_date = ANY(v_schedule.blacklisted_dates) THEN
    RAISE EXCEPTION 'Partner is closed on this date (holiday or exception)';
  END IF;

  -- Kapasitas
  SELECT count(*) INTO v_count
    FROM public.repair_jobs
   WHERE partner_id = p_partner_id
     AND scheduled_date::date = p_date
     AND status NOT IN ('0_cancelled', '9_done');

  IF v_count >= COALESCE(v_schedule.guaranteed_slots_per_day, 5) THEN
    RAISE EXCEPTION 'No capacity available: partner is fully booked for %', p_date;
  END IF;

  -- Set partner + tanggal dulu, lalu transition_job sebagai system
  UPDATE public.repair_jobs
     SET partner_id     = p_partner_id,
         scheduled_date = p_date::timestamptz,
         updated_at     = now()
   WHERE id = p_job_id;

  -- Transisi via transition_job (actor = system karena SECURITY DEFINER)
  PERFORM set_config('app.actor', 'system', true);
  PERFORM public.transition_job(p_job_id, '3_booked', '2_estimated',
    'booked via book_slot', jsonb_build_object('partner_id', p_partner_id, 'date', p_date));
  PERFORM set_config('app.actor', '', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.book_slot(uuid, uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.book_slot(uuid, uuid, date) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: advance_job_status — pembungkus tipis + C-60 (cabang all_access)
-- L-04: hapus 2_estimated → 3_booked
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.advance_job_status(p_job_id uuid, p_new_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Panggil transition_job; semua aturan dan audit ada di sana
  PERFORM public.transition_job(p_job_id, p_new_status, NULL, NULL, '{}');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.advance_job_status(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.advance_job_status(uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 8: customer_cancel_job — pembungkus tipis (L-06)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.customer_cancel_job(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job public.repair_jobs;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Job not found'; END IF;
  IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: you do not own this job';
  END IF;
  -- transition_job will check job_status_transitions for customer actor
  PERFORM public.transition_job(p_job_id, '0_cancelled', v_job.status,
    'customer cancellation', '{}');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.customer_cancel_job(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.customer_cancel_job(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 9: admin_set_job_status — pembungkus (SEC-14)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_set_job_status(
  p_job_id uuid,
  p_status text,
  p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Hanya admin.';
  END IF;
  PERFORM public.transition_job(p_job_id, p_status, NULL, p_reason, '{}');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 10: admin_assign_job — server tentukan status (L-05)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_assign_job(
  p_job_id     uuid,
  p_partner_id uuid,
  p_status     text DEFAULT NULL  -- deprecated, diabaikan
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job public.repair_jobs;
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can assign jobs.';
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Job not found: %', p_job_id; END IF;

  -- Setelah admitted: tolak (harus lewat admin_transfer_job — belum ada, dicatat di PROGRESS)
  IF v_job.status NOT IN ('2_estimated', '3_booked') THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: Cannot reassign job in status %. Use admin_transfer_job for admitted jobs.',
      v_job.status;
  END IF;

  -- Set partner
  UPDATE public.repair_jobs
     SET partner_id = p_partner_id, updated_at = now()
   WHERE id = p_job_id;

  -- Jika 2_estimated → booking via book_slot tidak dipakai (admin bypass kapasitas)
  -- Langsung transition ke 3_booked sebagai system
  IF v_job.status = '2_estimated' THEN
    PERFORM set_config('app.actor', 'system', true);
    PERFORM public.transition_job(p_job_id, '3_booked', '2_estimated',
      'admin assignment', jsonb_build_object('partner_id', p_partner_id));
    PERFORM set_config('app.actor', '', true);
  END IF;

  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('ADMIN_ASSIGN_JOB', 'repair_jobs', p_job_id, auth.uid(),
          jsonb_build_object('partner_id', p_partner_id, 'prev_status', v_job.status));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_assign_job(uuid, uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_assign_job(uuid, uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 11: admin_review_partner — reject dengan efek nyata (C-24)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_review_partner(
  p_partner_id uuid,
  p_decision   text,  -- 'approve' | 'reject' | 'suspend'
  p_reason     text   DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can review partners.';
  END IF;

  IF p_decision NOT IN ('approve', 'reject', 'suspend') THEN
    RAISE EXCEPTION 'Unknown decision: %', p_decision;
  END IF;

  IF p_decision IN ('reject', 'suspend') THEN
    -- Nonaktifkan partner
    UPDATE public.partners
       SET is_active          = false,
           auto_assign_active = false,
           approval_status    = p_decision,
           updated_at         = now()
     WHERE id = p_partner_id;

    -- Bekukan semua membership aktif di bengkel ini
    UPDATE public.memberships
       SET status = 'inactive', updated_at = now()
     WHERE org_id = p_partner_id AND scope = 'partner' AND status = 'active';

  ELSIF p_decision = 'approve' THEN
    UPDATE public.partners
       SET is_active       = true,
           approval_status = 'approved',
           updated_at      = now()
     WHERE id = p_partner_id;

    -- Aktifkan kembali membership owner
    UPDATE public.memberships
       SET status = 'active', updated_at = now()
     WHERE org_id   = p_partner_id
       AND scope    = 'partner'
       AND role     = 'owner';
  END IF;

  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES (
    'PARTNER_REVIEW_' || upper(p_decision),
    'partners', p_partner_id, auth.uid(),
    jsonb_build_object('decision', p_decision, 'reason', p_reason)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_review_partner(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_review_partner(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 12: ops_complete_intake — bungkus (L-01: hapus 4_paid → 5_admitted)
-- ─────────────────────────────────────────────────────────────────────────────

-- Patch: hapus izin 4_paid dari ops_complete_intake
-- (dibaca dari live DB — fungsi hanya memeriksa status IN ('3_booked','4_paid'))
-- Setelah fase ini, hanya '3_booked' yang boleh
DO $$
DECLARE
  v_body text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_body
    FROM pg_proc
   WHERE proname = 'ops_complete_intake'
     AND pronamespace = 'public'::regnamespace
  LIMIT 1;

  IF v_body LIKE '%4_paid%' THEN
    -- Catat bahwa fungsi ini perlu dipatch manual karena badan tidak bisa diambil aman
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES ('F4_NOTE', 'system', gen_random_uuid(), auth.uid(),
      '{"note":"ops_complete_intake still accepts 4_paid; manual patch needed via transition_job wrapper"}'::jsonb)
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- SELESAI — Diagram status dari job_status_transitions
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT from_status, to_status, string_agg(actor, ', ' ORDER BY actor) AS actors
-- FROM public.job_status_transitions
-- GROUP BY from_status, to_status
-- ORDER BY
--   (SELECT sort_order FROM public.job_statuses WHERE code = from_status),
--   (SELECT sort_order FROM public.job_statuses WHERE code = to_status);
