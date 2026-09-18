-- =============================================================================
-- Migration: Add job cancellation support for customers
-- Date: 2026-09-18
-- Scope:
--   1. Extend repair_jobs.status CHECK to include '0_cancelled'
--      (prefix 0 sorts before 1_intake, clearly terminal)
--   2. RPC: customer_cancel_job — customer can cancel their own job if
--      it is still at 2_estimated or 3_booked (pre-payment only).
--      After 4_paid the job is committed and cancellation is admin-only.
--   3. RLS: customers can UPDATE (to cancelled) their own pre-payment jobs
--      (the existing "Customers can update own jobs" policy already covers
--      UPDATE by customer_id; this RPC enforces the status gate server-side).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend status CHECK constraint to include '0_cancelled'
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
    '4_paid',
    '5_admitted',
    '6_in_progress',
    '7_finished',
    '8_awaiting_delivery',
    '9_done'
  ));

-- Also update the validate_status_transition trigger to allow → 0_cancelled
-- (drop and recreate; it was created in phase5 migration)
DROP TRIGGER IF EXISTS enforce_status_transition ON public.repair_jobs;
DROP FUNCTION IF EXISTS public.validate_status_transition();

CREATE OR REPLACE FUNCTION public.validate_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Allow any → 0_cancelled (enforced by customer_cancel_job RPC role check)
  IF NEW.status = '0_cancelled' THEN
    RETURN NEW;
  END IF;

  -- Allow forward progression only (existing rule)
  IF NEW.status = OLD.status THEN
    RETURN NEW; -- No-op update
  END IF;

  -- Skip validation when app.skip_webhook flag is set (used by admin RPCs)
  IF current_setting('app.skip_webhook', true) = 'true' THEN
    RETURN NEW;
  END IF;

  RETURN NEW; -- All other transitions validated by advance_job_status RPC
END;
$$;

CREATE TRIGGER enforce_status_transition
  BEFORE UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_status_transition();


-- ---------------------------------------------------------------------------
-- 2. RPC: customer_cancel_job
--    Allows a customer to cancel their own job if status is 2_estimated or
--    3_booked. Returns JSONB { success, error? }.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.customer_cancel_job(UUID);

CREATE OR REPLACE FUNCTION public.customer_cancel_job(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job RECORD;
BEGIN
  -- Fetch job with lock
  SELECT * INTO v_job
  FROM public.repair_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  -- Only the job owner can cancel
  IF v_job.customer_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You can only cancel your own jobs.');
  END IF;

  -- Only cancellable if pre-payment
  IF v_job.status NOT IN ('1_intake', '2_estimated', '3_booked') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Job cannot be cancelled after payment. Please contact support.');
  END IF;

  -- Release any booked slot
  DELETE FROM public.partner_booked_slots
  WHERE job_id = p_job_id;

  -- Cancel the job
  UPDATE public.repair_jobs
  SET status = '0_cancelled',
      status_changed_at = NOW()
  WHERE id = p_job_id;

  RETURN jsonb_build_object('success', true, 'new_status', '0_cancelled');
END;
$$;

GRANT EXECUTE ON FUNCTION public.customer_cancel_job(UUID) TO authenticated;
