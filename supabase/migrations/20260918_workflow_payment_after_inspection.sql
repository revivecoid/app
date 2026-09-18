-- =============================================================================
-- Migration: Workflow Redesign — Payment After Inspection
-- Date: 2026-09-18
-- New flow: book → admit → INSPECT (partner sets invoice) → pay → repair
--
-- Changes:
--   1. Add '3_inspected' to repair_jobs.status CHECK constraint
--      Positioned between 5_admitted and 4_paid in the actual workflow
--      (prefixed '3_' to sort before 4_paid alphabetically for legacy queries)
--   2. New RPC: partner_issue_invoice(job_id, final_cost)
--      Partner sets the real repair cost and advances job to 3_inspected
--      Notifies customer via send-notification edge function
--   3. Rebuild advance_job_status: 3_inspected → 4_paid allowed for customer
--      (customer confirms payment intent from invoice card)
--   4. Update validate_status_transition trigger to allow new status
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Extend repair_jobs.status CHECK constraint
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_constraint text;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.repair_jobs'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%status%';
  IF v_constraint IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.repair_jobs DROP CONSTRAINT ' || v_constraint;
  END IF;
END $$;

ALTER TABLE public.repair_jobs
  ADD CONSTRAINT repair_jobs_status_check
  CHECK (status IN (
    '0_cancelled',
    '1_intake',
    '2_estimated',
    '3_booked',
    '3_inspected',        -- NEW: partner completed physical inspection, invoice set
    '4_paid',
    '5_admitted',
    '6_in_progress',
    '7_finished',
    '8_awaiting_delivery',
    '9_done'
  ));


-- ---------------------------------------------------------------------------
-- 2. Rebuild validate_status_transition trigger to allow 3_inspected
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS enforce_status_transition ON public.repair_jobs;
DROP FUNCTION IF EXISTS public.validate_status_transition();

CREATE OR REPLACE FUNCTION public.validate_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = '0_cancelled' THEN RETURN NEW; END IF;
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF current_setting('app.skip_webhook', true) = 'true' THEN RETURN NEW; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_status_transition
  BEFORE UPDATE OF status ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.validate_status_transition();


-- ---------------------------------------------------------------------------
-- 3. New RPC: partner_issue_invoice
--    Called by partner after physical inspection.
--    Sets final_cost on the job and advances to 3_inspected.
--    Allowed callers: partner_mechanic, master_admin.
--    (partner_staff can assist inspection but invoice issuance is mechanic-level)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.partner_issue_invoice(UUID, NUMERIC);

CREATE OR REPLACE FUNCTION public.partner_issue_invoice(
  p_job_id    UUID,
  p_final_cost NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job         RECORD;
  v_caller_role TEXT;
  v_partner_id  UUID;
BEGIN
  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  IF v_caller_role NOT IN ('partner_mechanic', 'master_admin') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only workshop owners or admins can issue invoices.');
  END IF;

  IF p_final_cost IS NULL OR p_final_cost <= 0 THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Final cost must be a positive number.');
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  IF v_caller_role != 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false,
      'error', 'This job is not assigned to your workshop.');
  END IF;

  IF v_job.status != '5_admitted' THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Invoice can only be issued after vehicle is admitted. Current status: %s', v_job.status));
  END IF;

  UPDATE public.repair_jobs
  SET
    final_cost = p_final_cost,
    status = '3_inspected',
    status_changed_at = NOW()
  WHERE id = p_job_id;

  RETURN jsonb_build_object(
    'success', true,
    'job_id', p_job_id,
    'final_cost', p_final_cost,
    'new_status', '3_inspected',
    'customer_id', v_job.customer_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_issue_invoice(UUID, NUMERIC) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. Rebuild advance_job_status — add 3_inspected transitions
--    Workflow:
--      customer:         3_inspected → 4_paid  (confirms invoice & payment)
--      partner_mechanic: 4_paid → 6_in_progress (starts repair after payment confirmed)
--      partner_staff:    4_paid → 6_in_progress (also allowed to start)
--    All other transitions unchanged from previous migration.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.advance_job_status(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.advance_job_status(
  p_job_id     UUID,
  p_new_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job           RECORD;
  v_caller_role   TEXT;
  v_partner_id    UUID;
  v_allowed       BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_job
    FROM public.repair_jobs
   WHERE id = p_job_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  IF p_new_status NOT IN (
    '0_cancelled','1_intake','2_estimated','3_booked','3_inspected',
    '4_paid','5_admitted','6_in_progress','7_finished','8_awaiting_delivery','9_done'
  ) THEN
    RAISE EXCEPTION 'Invalid status value: %', p_new_status;
  END IF;

  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  CASE v_caller_role

    WHEN 'master_admin' THEN
      v_allowed := TRUE;

    WHEN 'customer' THEN
      v_allowed := (
        (v_job.status = '2_estimated'   AND p_new_status = '3_booked') OR
        (v_job.status = '3_inspected'   AND p_new_status = '4_paid')
      ) AND v_job.customer_id = auth.uid();

    WHEN 'partner_mechanic' THEN
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      v_allowed := (
        (v_job.status IN ('3_booked','4_paid')  AND p_new_status = '5_admitted') OR
        (v_job.status = '4_paid'                AND p_new_status = '6_in_progress') OR
        (v_job.status = '5_admitted'            AND p_new_status = '6_in_progress') OR
        (v_job.status = '6_in_progress'         AND p_new_status = '7_finished') OR
        (v_job.status = '7_finished'            AND p_new_status = '8_awaiting_delivery')
      );

    WHEN 'partner_staff' THEN
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      v_allowed := (
        (v_job.status IN ('3_booked','4_paid')  AND p_new_status = '5_admitted') OR
        (v_job.status = '4_paid'                AND p_new_status = '6_in_progress') OR
        (v_job.status = '5_admitted'            AND p_new_status = '6_in_progress') OR
        (v_job.status = '6_in_progress'         AND p_new_status = '7_finished')
      );

    WHEN 'partner_driver' THEN
      IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
        RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
      END IF;
      v_allowed := (
        v_job.status = '8_awaiting_delivery' AND p_new_status = '9_done'
      );

    ELSE
      v_allowed := FALSE;
  END CASE;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transition % → % not allowed for role %',
      v_job.status, p_new_status, v_caller_role;
  END IF;

  IF p_new_status = '5_admitted' AND v_job.status = '3_booked' THEN
    IF v_job.scheduled_date IS NOT NULL THEN
      INSERT INTO public.partner_booked_slots (partner_id, job_id, slot_date)
      VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  UPDATE public.repair_jobs
     SET status = p_new_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_job_status(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 5. Also allow customer to cancel from 3_inspected (they can reject invoice)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.customer_cancel_job(UUID);

CREATE OR REPLACE FUNCTION public.customer_cancel_job(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_job RECORD;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;
  IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can only cancel your own jobs.');
  END IF;
  -- Allow cancel up to and including 3_inspected (before payment is made)
  IF v_job.status NOT IN ('1_intake', '2_estimated', '3_booked', '3_inspected') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Job cannot be cancelled after payment. Please contact support.');
  END IF;
  DELETE FROM public.partner_booked_slots WHERE job_id = p_job_id;
  UPDATE public.repair_jobs
  SET status = '0_cancelled', status_changed_at = NOW()
  WHERE id = p_job_id;
  RETURN jsonb_build_object('success', true, 'new_status', '0_cancelled');
END;
$$;

GRANT EXECUTE ON FUNCTION public.customer_cancel_job(UUID) TO authenticated;
