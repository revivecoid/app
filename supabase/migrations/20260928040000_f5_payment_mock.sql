-- =============================================================================
-- 20260928040000_f5_payment_mock.sql
-- Fase 5: Pembayaran mock yang aman dan siap diganti gateway
--
-- Mengatasi: B-01, BIZ-01, BIZ-04, BIZ-08, BIZ-11, BIZ-13, C-04, C-72
-- Dart: C-38, C-49, S-07, UX-06 (handled in Dart files)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: Sequence untuk nomor referensi
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS public.payment_ref_seq START 1000 INCREMENT 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: Tabel payments (BIZ-13)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.payments (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id           uuid        NOT NULL REFERENCES public.repair_jobs(id) ON DELETE RESTRICT,
  reference        text        UNIQUE NOT NULL,
  amount           bigint      NOT NULL CHECK (amount > 0),
  breakdown        jsonb       NOT NULL DEFAULT '{}',
  method           text        NOT NULL CHECK (method IN ('mock','manual_transfer','gateway')),
  provider         text        NOT NULL DEFAULT 'mock',
  provider_ref     text,
  status           text        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending','awaiting_review','paid','rejected','expired','cancelled')),
  proof_file_key   text,
  idempotency_key  text        UNIQUE NOT NULL,
  created_by       uuid        REFERENCES auth.users(id),
  reviewed_by      uuid        REFERENCES auth.users(id),
  reviewed_at      timestamptz,
  review_note      text,
  paid_at          timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Partial unique: satu pembayaran aktif per job
CREATE UNIQUE INDEX IF NOT EXISTS payments_job_active_unique
  ON public.payments(job_id)
  WHERE status IN ('pending','awaiting_review');

CREATE INDEX IF NOT EXISTS idx_payments_job_id  ON public.payments(job_id);
CREATE INDEX IF NOT EXISTS idx_payments_status  ON public.payments(status, created_at);

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customer reads own job payments"  ON public.payments;
DROP POLICY IF EXISTS "Admin reads all payments"         ON public.payments;
DROP POLICY IF EXISTS "Partner reads their job payments" ON public.payments;

CREATE POLICY "Customer reads own job payments" ON public.payments
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.repair_jobs j WHERE j.id = job_id AND j.customer_id = auth.uid()
  ));

CREATE POLICY "Admin reads all payments" ON public.payments
  FOR SELECT TO authenticated USING (is_master_admin());

-- Partner: baca status saja (bukan proof_file_key) — enforced di app layer
CREATE POLICY "Partner reads their job payments" ON public.payments
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.repair_jobs j
    WHERE j.id = job_id AND j.partner_id IS NOT NULL
      AND has_partner_membership(j.partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[])
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: payment_events — jejak audit
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.payment_events (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id  uuid        NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  event       text        NOT NULL,
  actor       uuid        REFERENCES auth.users(id),
  data        jsonb       NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payment_events_payment ON public.payment_events(payment_id);
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin reads payment events" ON public.payment_events
  FOR SELECT TO authenticated USING (is_master_admin());
CREATE POLICY "Customer reads own payment events" ON public.payment_events
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.payments p
    JOIN public.repair_jobs j ON j.id = p.job_id
    WHERE p.id = payment_id AND j.customer_id = auth.uid()
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: app_settings — payment_mode, valet_fee, mock_autosettle
-- ─────────────────────────────────────────────────────────────────────────────

-- Pakai cms_settings yang sudah ada bila ada; fallback ke app_settings baru
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'app_settings') THEN
    CREATE TABLE public.app_settings (
      key   text PRIMARY KEY,
      value jsonb NOT NULL DEFAULT 'null'
    );
    ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Admin manages app_settings" ON public.app_settings
      FOR ALL TO authenticated USING (is_master_admin()) WITH CHECK (is_master_admin());
    CREATE POLICY "Authenticated reads app_settings" ON public.app_settings
      FOR SELECT TO authenticated USING (true);
  END IF;
END;
$$;

INSERT INTO public.app_settings (key, value) VALUES
  ('payment_mode',    '"mock"'),
  ('mock_autosettle', 'false'),
  ('valet_fee_base',  '50000')   -- Rp 50.000 flat, dikonfirmasi pemilik repo
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: settle_payment — internal, tidak di-GRANT ke authenticated (B-01)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.settle_payment(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pay  public.payments;
  v_job  public.repair_jobs;
BEGIN
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found: %', p_payment_id; END IF;
  IF v_pay.status = 'paid' THEN RETURN; END IF;  -- idempotent
  IF v_pay.status NOT IN ('pending','awaiting_review') THEN
    RAISE EXCEPTION 'Cannot settle payment in status %', v_pay.status;
  END IF;

  UPDATE public.payments
     SET status = 'paid', paid_at = now()
   WHERE id = p_payment_id;

  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (p_payment_id, 'settled', auth.uid(),
    jsonb_build_object('reference', v_pay.reference, 'amount', v_pay.amount));

  -- Transisi job ke 4_paid via transition_job (system actor)
  PERFORM set_config('app.actor', 'system', true);
  PERFORM public.transition_job(
    v_pay.job_id, '4_paid', '3_inspected',
    'payment:' || v_pay.reference, '{}'
  );
  PERFORM set_config('app.actor', '', true);
END;
$$;

-- TIDAK di-GRANT ke authenticated — hanya service_role dan internal
REVOKE EXECUTE ON FUNCTION public.settle_payment(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.settle_payment(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: create_payment — pelanggan membuat tagihan (BIZ-13)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_payment(
  p_job_id          uuid,
  p_method          text,
  p_idempotency_key text
) RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job    public.repair_jobs;
  v_pay    public.payments;
  v_amount bigint;
  v_ref    text;
  v_valet  bigint;
  v_breakdown jsonb;
BEGIN
  -- Cek idempotency dulu
  SELECT * INTO v_pay FROM public.payments WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN RETURN v_pay; END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Job not found: %', p_job_id; END IF;

  IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: you do not own this job';
  END IF;
  IF v_job.status <> '3_inspected' THEN
    RAISE EXCEPTION 'Payment requires job status 3_inspected, got %', v_job.status;
  END IF;
  IF v_job.final_cost IS NULL THEN
    RAISE EXCEPTION 'Job has no final_cost — partner must issue invoice first';
  END IF;
  IF p_method NOT IN ('mock','manual_transfer') THEN
    RAISE EXCEPTION 'Invalid payment method: %', p_method;
  END IF;

  -- Hitung amount server-side (C-72: round, bukan floor)
  v_amount := round(v_job.final_cost)::bigint;

  -- Biaya valet (BIZ-08)
  v_valet := 0;
  IF v_job.delivery_type = 'pickup' THEN
    SELECT (value::text::bigint) INTO v_valet
      FROM public.app_settings WHERE key = 'valet_fee_base';
    v_valet := COALESCE(v_valet, 50000);
    v_amount := v_amount + v_valet;
  END IF;

  v_breakdown := jsonb_build_object(
    'repair_cost', round(v_job.final_cost)::bigint,
    'valet_fee',   v_valet,
    'total',       v_amount
  );

  -- Nomor referensi
  v_ref := 'REV-' || to_char(now(), 'YYYY') || '-' ||
            lpad(nextval('public.payment_ref_seq')::text, 6, '0');

  INSERT INTO public.payments
    (job_id, reference, amount, breakdown, method, idempotency_key, created_by)
  VALUES
    (p_job_id, v_ref, v_amount, v_breakdown, p_method, p_idempotency_key, auth.uid())
  RETURNING * INTO v_pay;

  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (v_pay.id, 'created', auth.uid(),
    jsonb_build_object('method', p_method, 'amount', v_amount, 'reference', v_ref));

  RETURN v_pay;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_payment(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_payment(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: submit_payment_proof — manual transfer
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_payment_proof(
  p_payment_id uuid,
  p_file_key   text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pay public.payments;
  v_job public.repair_jobs;
BEGIN
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = v_pay.job_id;
  IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'forbidden: you do not own this payment';
  END IF;
  IF v_pay.status <> 'pending' THEN
    RAISE EXCEPTION 'Payment already submitted (status: %)', v_pay.status;
  END IF;
  IF v_pay.method <> 'manual_transfer' THEN
    RAISE EXCEPTION 'Proof upload only for manual_transfer';
  END IF;
  -- Validasi prefix kunci storage (C-03)
  IF p_file_key NOT LIKE 'jobs/' || v_pay.job_id::text || '/payment_proof/%' THEN
    RAISE EXCEPTION 'Invalid file key prefix for payment proof';
  END IF;

  UPDATE public.payments
     SET status = 'awaiting_review', proof_file_key = p_file_key
   WHERE id = p_payment_id;

  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (p_payment_id, 'proof_submitted', auth.uid(),
    jsonb_build_object('file_key', p_file_key));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_payment_proof(uuid, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_payment_proof(uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 8: admin_review_payment (C-04)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_review_payment(
  p_payment_id uuid,
  p_approve    boolean,
  p_note       text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pay public.payments;
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only admins can review payments';
  END IF;

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
  IF v_pay.status NOT IN ('pending','awaiting_review') THEN
    RAISE EXCEPTION 'Payment not in reviewable status: %', v_pay.status;
  END IF;

  IF p_approve THEN
    -- Settle
    UPDATE public.payments
       SET reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note
     WHERE id = p_payment_id;
    PERFORM public.settle_payment(p_payment_id);
  ELSE
    UPDATE public.payments
       SET status = 'rejected', reviewed_by = auth.uid(),
           reviewed_at = now(), review_note = p_note
     WHERE id = p_payment_id;

    INSERT INTO public.payment_events (payment_id, event, actor, data)
    VALUES (p_payment_id, 'rejected', auth.uid(),
      jsonb_build_object('note', p_note));

    -- Notifikasi pelanggan
    DECLARE v_job public.repair_jobs;
    BEGIN
      SELECT * INTO v_job FROM public.repair_jobs WHERE id = v_pay.job_id;
      PERFORM public.enqueue_job_notification(
        v_pay.job_id, v_job.customer_id, 'payment_rejected',
        jsonb_build_object('reference', v_pay.reference, 'note', p_note)
      );
    END;
  END IF;

  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES (
    CASE WHEN p_approve THEN 'PAYMENT_APPROVED' ELSE 'PAYMENT_REJECTED' END,
    'payments', p_payment_id, auth.uid(),
    jsonb_build_object('approved', p_approve, 'note', p_note, 'reference', v_pay.reference)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_review_payment(uuid, boolean, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_review_payment(uuid, boolean, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 9: mock_settle_payment — simulasi (B-01, BIZ-01)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mock_settle_payment(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pay          public.payments;
  v_mode         text;
  v_autosettle   boolean;
BEGIN
  SELECT value::text::text INTO v_mode
    FROM public.app_settings WHERE key = 'payment_mode';
  IF v_mode IS DISTINCT FROM '"mock"' THEN
    RAISE EXCEPTION 'mock_settle_payment only available in mock payment mode';
  END IF;

  SELECT (value::text)::boolean INTO v_autosettle
    FROM public.app_settings WHERE key = 'mock_autosettle';

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;

  -- Admin selalu boleh; pelanggan hanya jika autosettle=true
  IF NOT is_master_admin() THEN
    IF NOT COALESCE(v_autosettle, false) THEN
      RAISE EXCEPTION 'mock_autosettle is disabled — only admin can settle in mock mode';
    END IF;
    DECLARE v_job public.repair_jobs;
    BEGIN
      SELECT * INTO v_job FROM public.repair_jobs WHERE id = v_pay.job_id;
      IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'forbidden: you do not own this payment';
      END IF;
    END;
  END IF;

  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (p_payment_id, 'mock_settled', auth.uid(),
    jsonb_build_object('note', 'SIMULASI — tidak ada dana yang ditagih'));

  PERFORM public.settle_payment(p_payment_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mock_settle_payment(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mock_settle_payment(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 10: BIZ-04 — view partner_settlements untuk settlement harian
-- Fix: gunakan paid_at dan status='paid', bukan status='completed'
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.partner_settlements;
CREATE VIEW public.partner_settlements AS
  SELECT
    p.id              AS partner_id,
    p.shop_name,
    date_trunc('day', py.paid_at) AS settlement_date,
    count(py.id)      AS payment_count,
    sum(py.amount)    AS gross_amount,
    sum(round(py.amount * COALESCE(p.commission_rate, 0.1)))::bigint AS commission,
    sum(py.amount - round(py.amount * COALESCE(p.commission_rate, 0.1)))::bigint AS net_payout
  FROM public.payments py
  JOIN public.repair_jobs j  ON j.id = py.job_id
  JOIN public.partners p     ON p.id = j.partner_id
  WHERE py.status = 'paid'
  GROUP BY p.id, p.shop_name, date_trunc('day', py.paid_at);

GRANT SELECT ON public.partner_settlements TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 11: Hapus 3_inspected → 4_paid untuk customer dari job_status_transitions (B-01)
-- Transisi ini sekarang hanya lewat settle_payment (system actor)
-- ─────────────────────────────────────────────────────────────────────────────

DELETE FROM public.job_status_transitions
WHERE from_status = '3_inspected'
  AND to_status   = '4_paid'
  AND actor       = 'customer';

-- Juga hapus advance_job_status customer path ke 4_paid sudah tertutup oleh F4
-- (transition_job cek tabel transisi — tidak ada baris customer → 4_paid lagi)

-- ─────────────────────────────────────────────────────────────────────────────
-- SELESAI — Verifikasi
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname IN ('create_payment','submit_payment_proof','admin_review_payment',
--                   'settle_payment','mock_settle_payment')
-- ORDER BY proname;
--
-- SELECT count(*) FROM public.job_status_transitions
--   WHERE from_status='3_inspected' AND to_status='4_paid' AND actor='customer';
-- -- Harus 0
