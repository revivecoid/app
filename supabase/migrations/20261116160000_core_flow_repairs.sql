-- Core flow repairs — findings 1, 2, 3 and 5 of the 16 Nov 2026 CTO review.
--
-- 5. create_job_from_estimation could never create an order. It wrote the
--    caller's service_area text straight into service_area_enum (22P02) and
--    inserted photos into repair_photos using columns that table does not have
--    (file_key, uploaded_by — the real ones are r2_file_key, and there is no
--    uploader column). Every "estimate → order" attempt died, so the customer
--    flow stopped at the estimator.
-- 2. admin_release_invoice released the invoice and moved the job to
--    3_inspected but never copied invoices.final_cost into repair_jobs.final_cost,
--    so the customer's pay page read NULL (Rp 0) and create_payment refused the
--    job with "Final cost is not set".
-- 3. settle_payment settled the payment and moved the job to 4_paid but left
--    invoices.status at 'released', so the invoice never showed as paid.
-- 1. execute_auto_assign ignored auto_assign_settings.is_active, so the admin
--    toggle was decorative; the booking screen then swallowed the raised error
--    and told the customer "Booking confirmed!" with no partner attached.

-- ── 1. Service areas ────────────────────────────────────────────────────────
-- service_areas carries 12 rows; the enum is missing the two that were added
-- later. Without them a job filed in Surabaya or Tangerang Selatan silently
-- loses its area (and auto-assign cannot match location).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
     WHERE enumtypid = 'public.service_area_enum'::regtype
       AND enumlabel = 'Tangerang Selatan'
  ) THEN
    ALTER TYPE public.service_area_enum ADD VALUE 'Tangerang Selatan';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
     WHERE enumtypid = 'public.service_area_enum'::regtype
       AND enumlabel = 'Surabaya'
  ) THEN
    ALTER TYPE public.service_area_enum ADD VALUE 'Surabaya';
  END IF;
END;
$$;

-- ── 2. Estimation → job ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_job_from_estimation(
  p_estimation_id uuid,
  p_vehicle_make text,
  p_vehicle_model text,
  p_vehicle_year integer,
  p_license_plate text,
  p_contact_phone text DEFAULT NULL::text,
  p_service_area text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id    uuid := auth.uid();
  v_est        public.estimations;
  v_vehicle    RECORD;
  v_job_id     uuid;
  v_norm_plate text;
  v_area_input text;
  v_area_label text;
  v_area       public.service_area_enum;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Login required'; END IF;
  SELECT * INTO v_est FROM public.estimations WHERE id = p_estimation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ESTIMATION_ERROR: Not found'; END IF;
  IF v_est.status <> 'success' THEN RAISE EXCEPTION 'ESTIMATION_ERROR: status is %, must be success', v_est.status; END IF;
  IF v_est.expires_at < now() THEN RAISE EXCEPTION 'ESTIMATION_ERROR: Estimation expired'; END IF;
  IF v_est.total <= 0 THEN RAISE EXCEPTION 'ESTIMATION_ERROR: Zero cost — at least one panel required'; END IF;
  IF v_est.user_id IS NOT NULL AND v_est.user_id <> v_user_id THEN RAISE EXCEPTION 'ESTIMATION_ERROR: Not your estimation'; END IF;

  v_norm_plate := CASE WHEN p_license_plate IS NULL OR trim(p_license_plate) = '' THEN NULL
    ELSE upper(regexp_replace(trim(p_license_plate), '[^A-Z0-9]', '', 'g')) END;

  -- The column is an enum whose labels are the display names ("Jakarta
  -- Selatan"), while callers send either a service_areas.code or the label
  -- itself. Resolve the code to its label, then cast; an unknown value becomes
  -- NULL instead of aborting the whole order.
  v_area_input := NULLIF(btrim(p_service_area), '');
  IF v_area_input IS NOT NULL THEN
    SELECT sa.label INTO v_area_label
      FROM public.service_areas sa
     WHERE lower(sa.code) = lower(v_area_input)
        OR lower(sa.label) = lower(v_area_input)
     LIMIT 1;
    v_area_label := COALESCE(v_area_label, v_area_input);
    BEGIN
      v_area := v_area_label::public.service_area_enum;
    EXCEPTION WHEN invalid_text_representation THEN
      v_area := NULL;
    END;
  END IF;

  INSERT INTO public.vehicles (customer_id, make, model, year, license_plate)
  VALUES (v_user_id, trim(p_vehicle_make), trim(p_vehicle_model), p_vehicle_year, v_norm_plate)
  ON CONFLICT (customer_id, license_plate) DO UPDATE
    SET make=EXCLUDED.make, model=EXCLUDED.model, year=EXCLUDED.year, updated_at=now()
  RETURNING * INTO v_vehicle;

  INSERT INTO public.repair_jobs (customer_id, vehicle_id, initial_estimation_cost, estimation_result, status, service_area, contact_phone)
  VALUES (v_user_id, v_vehicle.id, v_est.total,
    jsonb_build_object('estimation_id',v_est.id,'panels',v_est.panels,'model',v_est.model,'photo_keys',v_est.photo_keys),
    '2_estimated', v_area, normalize_id_phone(p_contact_phone))
  RETURNING id INTO v_job_id;

  -- repair_photos records the object key in r2_file_key. The uploader is not
  -- stored: the job already belongs to this customer.
  IF v_est.photo_keys IS NOT NULL THEN
    INSERT INTO public.repair_photos (job_id, step_context, r2_file_key)
    SELECT v_job_id, 'estimate', btrim(k)
      FROM unnest(v_est.photo_keys) AS k
     WHERE k IS NOT NULL
       AND btrim(k) <> ''
       AND NOT EXISTS (
         SELECT 1 FROM public.repair_photos rp
          WHERE rp.job_id = v_job_id AND rp.r2_file_key = btrim(k)
       );
  END IF;

  UPDATE public.estimations SET expires_at = now() WHERE id = p_estimation_id;
  RETURN v_job_id;
END;
$function$;

-- ── 3. Release invoice: carry the total onto the job ───────────────────────
CREATE OR REPLACE FUNCTION public.admin_release_invoice(p_invoice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_inv      RECORD;
  v_cfg      RECORD;
  v_deadline TIMESTAMPTZ;
BEGIN
  IF NOT public.is_master_admin() THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only a platform admin can release an invoice.');
  END IF;

  SELECT * INTO v_inv FROM public.invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found.');
  END IF;

  IF v_inv.status <> 'awaiting_release' THEN
    RETURN jsonb_build_object('success', false, 'error', format(
      'Only a checked invoice can be released. Current status: %s', v_inv.status));
  END IF;

  SELECT * INTO v_cfg FROM public.payment_config WHERE id = 1;
  v_deadline := now() + make_interval(hours => COALESCE(v_cfg.payment_window_hours, 24));

  UPDATE public.invoices
     SET status = 'released', released_at = now(), released_by = auth.uid(),
         expires_at = v_deadline,
         payment_method = COALESCE(payment_method,
           CASE WHEN COALESCE(v_cfg.online_enabled, false)
                THEN v_cfg.primary_provider ELSE 'manual_transfer' END)
   WHERE id = p_invoice_id;

  -- The job's final_cost is what the pay page, create_payment and the ops app
  -- read. Without it the invoice amount exists only on the invoice row.
  -- The status move stays limited to jobs still in the bay so that a
  -- re-release after a correction cannot drag a job backwards.
  UPDATE public.repair_jobs
     SET final_cost = v_inv.final_cost,
         status = CASE WHEN status = '5_admitted' THEN '3_inspected' ELSE status END,
         status_changed_at = CASE WHEN status = '5_admitted' THEN now() ELSE status_changed_at END
   WHERE id = v_inv.job_id;

  PERFORM public.notify(
    'invoice_released_detail',
    'Invoice ' || v_inv.invoice_number || ' Diterbitkan',
    format('Total perbaikan Anda: Rp %s. Silakan tinjau dan setujui invoice di aplikasi sebelum %s.',
           to_char(v_inv.final_cost, 'FM999G999G999G999'),
           to_char(v_deadline, 'DD Mon YYYY HH24:MI')),
    v_inv.job_id, 'customer',
    jsonb_build_object('invoice_id', p_invoice_id, 'invoice_number', v_inv.invoice_number,
                       'final_cost', v_inv.final_cost));

  RETURN jsonb_build_object(
    'success', true, 'invoice_status', 'released',
    'invoice_number', v_inv.invoice_number, 'expires_at', v_deadline);
END;
$function$;

-- ── 4. Settlement also closes the invoice ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.settle_payment(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pay public.payments;
BEGIN
  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found: %', p_payment_id; END IF;
  IF v_pay.status = 'paid' THEN RETURN; END IF;
  IF v_pay.status NOT IN ('pending','awaiting_review') THEN
    RAISE EXCEPTION 'Cannot settle payment in status %', v_pay.status;
  END IF;
  UPDATE public.payments SET status = 'paid', paid_at = now() WHERE id = p_payment_id;
  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (p_payment_id, 'settled', auth.uid(),
    jsonb_build_object('reference', v_pay.reference, 'amount', v_pay.amount));

  -- The invoice is the customer's proof of payment; it must leave 'released'.
  UPDATE public.invoices
     SET status = 'paid',
         paid_at = COALESCE(paid_at, now()),
         payment_method = COALESCE(payment_method, v_pay.method),
         payment_reference = COALESCE(payment_reference, v_pay.reference)
   WHERE job_id = v_pay.job_id
     AND status IN ('released', 'approved');

  PERFORM set_config('app.actor', 'system', true);
  PERFORM public.transition_job(v_pay.job_id, '4_paid', '3_inspected',
    'payment:' || v_pay.reference, '{}');
  PERFORM set_config('app.actor', '', true);
END;
$function$;

-- ── 5. Admin records a payment that never had a gateway row ────────────────
-- Cash or a transfer confirmed outside the app. Writes a real payment row so
-- the job, the invoice and the audit trail agree, instead of the admin panel
-- pretending a slip exists.
CREATE OR REPLACE FUNCTION public.admin_record_manual_payment(
  p_job_id uuid,
  p_amount bigint DEFAULT NULL,
  p_method text DEFAULT 'manual_transfer',
  p_reference text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job    public.repair_jobs;
  v_amount bigint;
  v_ref    text;
  v_pay_id uuid;
  v_method text := COALESCE(NULLIF(btrim(p_method), ''), 'manual_transfer');
BEGIN
  IF NOT public.is_master_admin() THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only a platform admin can record a payment.');
  END IF;
  IF v_method NOT IN ('manual_transfer', 'mock') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Manual payments must be manual_transfer.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;
  IF v_job.status IN ('4_paid','6_in_progress','7_finished','8_awaiting_delivery','9_done') THEN
    RETURN jsonb_build_object('success', false, 'error', 'This job is already paid.');
  END IF;
  IF v_job.status <> '3_inspected' THEN
    RETURN jsonb_build_object('success', false, 'error', format(
      'A payment can only be recorded after inspection. Current status: %s', v_job.status));
  END IF;

  v_amount := COALESCE(p_amount, v_job.final_cost::bigint);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Final cost is not set for this job.');
  END IF;

  v_ref := COALESCE(NULLIF(btrim(p_reference), ''),
    'MANUAL-' || upper(substr(p_job_id::text, 1, 8)) || '-' || to_char(now(), 'YYMMDDHH24MISS'));

  INSERT INTO public.payments
    (job_id, reference, amount, breakdown, method, provider, status,
     idempotency_key, created_by, reviewed_by, reviewed_at, review_note)
  VALUES
    (p_job_id, v_ref, v_amount, '{}'::jsonb, v_method, 'manual', 'pending',
     'manual:' || p_job_id::text || ':' || v_ref, auth.uid(), auth.uid(), now(), p_note)
  RETURNING id INTO v_pay_id;

  INSERT INTO public.payment_events (payment_id, event, actor, data)
  VALUES (v_pay_id, 'created', auth.uid(),
    jsonb_build_object('amount', v_amount, 'reference', v_ref, 'manual', true));

  PERFORM public.settle_payment(v_pay_id);

  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('MANUAL_PAYMENT_RECORDED', 'payments', v_pay_id, auth.uid(),
    jsonb_build_object('job_id', p_job_id, 'amount', v_amount,
                       'reference', v_ref, 'note', p_note));

  RETURN jsonb_build_object('success', true, 'payment_id', v_pay_id,
    'reference', v_ref, 'amount', v_amount, 'job_status', '4_paid');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_record_manual_payment(uuid, bigint, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_record_manual_payment(uuid, bigint, text, text, text) TO authenticated;

-- ── 6. Auto-assign: honour the switch, and switch it on ────────────────────
CREATE OR REPLACE FUNCTION public.execute_auto_assign(p_job_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job public.repair_jobs; v_settings public.auto_assign_settings;
  v_partner_id uuid; v_target_date date; v_log_note text := '';
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Job not found'; END IF;
  IF v_job.customer_id <> auth.uid() THEN RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Only job owner can trigger auto-assign'; END IF;
  IF v_job.status <> '2_estimated' THEN RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Job must be 2_estimated, got %', v_job.status; END IF;
  SELECT * INTO v_settings FROM public.auto_assign_settings LIMIT 1;
  IF NOT FOUND OR NOT COALESCE(v_settings.is_active, false) THEN
    RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: Auto-assign is disabled; the job waits for an admin to assign a workshop';
  END IF;
  v_target_date := COALESCE(v_job.scheduled_date::date, CURRENT_DATE + 1);

  SELECT p.id INTO v_partner_id
  FROM public.partners p
  JOIN public.memberships m ON m.org_id = p.id AND m.role = 'owner' AND m.status = 'active'
  WHERE p.is_active = true AND p.status = 'approved'
    AND (NOT COALESCE(v_settings.match_location, false) OR v_job.service_area IS NULL
         OR p.service_area IS NULL OR p.service_area = v_job.service_area)
    AND (SELECT available FROM public.partner_day_capacity(p.id, v_target_date)) > 0
    AND NOT EXISTS (SELECT 1 FROM public.holidays WHERE date = v_target_date)
  ORDER BY (SELECT used FROM public.partner_day_capacity(p.id, v_target_date)) ASC
  LIMIT 1;

  IF v_partner_id IS NULL AND COALESCE(v_settings.match_location, false) AND v_job.service_area IS NOT NULL THEN
    v_log_note := 'location_match_fallback: no partner in area ' || v_job.service_area;
    SELECT p.id INTO v_partner_id
    FROM public.partners p
    JOIN public.memberships m ON m.org_id = p.id AND m.role = 'owner' AND m.status = 'active'
    WHERE p.is_active = true AND p.status = 'approved'
      AND (SELECT available FROM public.partner_day_capacity(p.id, v_target_date)) > 0
      AND NOT EXISTS (SELECT 1 FROM public.holidays WHERE date = v_target_date)
    ORDER BY (SELECT used FROM public.partner_day_capacity(p.id, v_target_date)) ASC
    LIMIT 1;
  END IF;

  IF v_partner_id IS NULL THEN RAISE EXCEPTION 'AUTO_ASSIGN_ERROR: No eligible partner found for date %', v_target_date; END IF;
  PERFORM public.book_slot(p_job_id, v_partner_id, v_target_date);
  IF v_log_note <> '' THEN
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES ('AUTO_ASSIGN_FALLBACK','repair_jobs',p_job_id,auth.uid(),jsonb_build_object('note',v_log_note,'assigned_partner',v_partner_id));
  END IF;
  RETURN v_partner_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.execute_auto_assign(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.execute_auto_assign(uuid) TO authenticated;

-- The designed flow books automatically. Leaving this off is what made every
-- booking end without a workshop.
UPDATE public.auto_assign_settings
   SET is_active = true, updated_at = now()
 WHERE id = 1 AND is_active IS DISTINCT FROM true;
