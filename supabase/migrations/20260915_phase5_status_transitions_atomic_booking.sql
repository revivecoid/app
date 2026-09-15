-- ═══════════════════════════════════════════════════════════════════════════════
-- PHASE 5 REMEDIATION: Business Logic — Status Transitions & Atomic Booking
-- Fixes: BIZ-02, BIZ-05, BIZ-03
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- BIZ-02: Server-side status transition validation
-- Previously all status changes were done via direct UPDATE with no validation.
-- A customer could update their job status to any arbitrary string.
-- ─────────────────────────────────────────────────────────────────────────────

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
BEGIN
  -- Fetch current job state with a lock to prevent race conditions
  SELECT * INTO v_job
    FROM public.repair_jobs
   WHERE id = p_job_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;

  -- Determine caller role and partner
  v_caller_role := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner_id  := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  -- ── Validate allowed transitions ──────────────────────────────────────────
  -- Allowed transition map:
  --   customer:         2_estimated → 3_booked
  --   customer:         3_booked    → 4_paid  (after payment confirmation)
  --   partner_mechanic: 4_paid|3_booked → 5_admitted
  --   partner_mechanic: 5_admitted → 6_in_progress
  --   partner_mechanic: 6_in_progress → 7_finished
  --   partner_mechanic: 7_finished → 8_awaiting_delivery
  --   master_admin:     any valid transition

  IF v_caller_role = 'master_admin' THEN
    -- Admin can make any valid status transition
    IF p_new_status NOT IN (
      '1_intake','2_estimated','3_booked','4_paid','5_admitted',
      '6_in_progress','7_finished','8_awaiting_delivery','9_done'
    ) THEN
      RAISE EXCEPTION 'Invalid status value: %', p_new_status;
    END IF;

  ELSIF v_caller_role IN ('partner_mechanic', 'partner_staff') THEN
    -- Partner must own this job
    IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
      RAISE EXCEPTION 'forbidden: you are not assigned to this job';
    END IF;
    -- Partner allowed transitions
    IF NOT (
      (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
      (v_job.status = '5_admitted'           AND p_new_status = '6_in_progress') OR
      (v_job.status = '6_in_progress'        AND p_new_status = '7_finished') OR
      (v_job.status = '7_finished'           AND p_new_status = '8_awaiting_delivery') OR
      (v_job.status = '8_awaiting_delivery'  AND p_new_status = '9_done')
    ) THEN
      RAISE EXCEPTION 'forbidden: invalid status transition % → % for partner role',
        v_job.status, p_new_status;
    END IF;
    -- BIZ-03: Partner cannot admit job unless payment confirmed
    IF p_new_status = '5_admitted' AND v_job.status = '3_booked' THEN
      -- Allow bypass only if initial_estimation_cost is 0 (waived jobs)
      IF COALESCE(v_job.initial_estimation_cost, 0) > 0 THEN
        RAISE EXCEPTION 'forbidden: payment must be confirmed (status 4_paid) before admission';
      END IF;
    END IF;

  ELSE
    -- Customer allowed transitions
    IF auth.uid() IS DISTINCT FROM v_job.customer_id THEN
      RAISE EXCEPTION 'forbidden: this is not your job';
    END IF;
    IF NOT (
      (v_job.status = '2_estimated' AND p_new_status = '3_booked')
    ) THEN
      RAISE EXCEPTION 'forbidden: customers can only confirm a booking (2_estimated → 3_booked), got % → %',
        v_job.status, p_new_status;
    END IF;
  END IF;

  -- ── Apply the transition ───────────────────────────────────────────────────
  UPDATE public.repair_jobs
     SET status           = p_new_status,
         status_changed_at = NOW(),
         updated_at        = NOW()
   WHERE id = p_job_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_job_status(UUID, TEXT)
  TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- BIZ-05: Atomic slot booking — prevents race condition double-booking
-- Previously the client checked availability then inserted in two separate queries.
-- Between those two calls another request could claim the same slot.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.book_slot(
  p_job_id     UUID,
  p_partner_id UUID,
  p_date       DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job          RECORD;
  v_schedule     RECORD;
  v_existing_count INTEGER;
  v_date_str     TEXT;
  v_weekday      INTEGER;
BEGIN
  -- Verify caller owns the job
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found: %', p_job_id;
  END IF;
  IF v_job.customer_id IS DISTINCT FROM auth.uid() AND
     NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: you do not own this job';
  END IF;

  v_date_str := p_date::TEXT; -- YYYY-MM-DD
  v_weekday  := EXTRACT(DOW FROM p_date)::INTEGER;
  -- Convert Sunday=0 to 7 for ISO weekday compatibility (1=Mon,7=Sun)
  IF v_weekday = 0 THEN v_weekday := 7; END IF;

  -- Fetch partner schedule
  SELECT * INTO v_schedule
    FROM public.partner_schedules
   WHERE partner_id = p_partner_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No schedule configured for partner: %', p_partner_id;
  END IF;

  -- Check working day
  IF NOT (v_schedule.standard_working_days @> ARRAY[v_weekday]) THEN
    RAISE EXCEPTION 'Partner does not work on this day of the week';
  END IF;

  -- Check blacklisted dates (holidays + manual exceptions)
  IF v_schedule.blacklisted_dates @> ARRAY[v_date_str] THEN
    RAISE EXCEPTION 'Partner is closed on this date (holiday or exception)';
  END IF;

  -- BIZ-05: Atomic capacity check + insert under the row lock from above
  SELECT COUNT(*) INTO v_existing_count
    FROM public.repair_jobs
   WHERE partner_id    = p_partner_id
     AND scheduled_date >= (p_date::TIMESTAMP WITH TIME ZONE)
     AND scheduled_date <  (p_date::TIMESTAMP WITH TIME ZONE + INTERVAL '1 day');

  IF v_existing_count >= COALESCE(v_schedule.guaranteed_slots_per_day, 5) THEN
    RAISE EXCEPTION 'No capacity available: partner is fully booked for %', v_date_str;
  END IF;

  -- Update the job with the chosen partner and date
  UPDATE public.repair_jobs
     SET partner_id     = p_partner_id,
         scheduled_date = p_date::TIMESTAMP WITH TIME ZONE,
         status         = '3_booked',
         updated_at     = NOW()
   WHERE id = p_job_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.book_slot(UUID, UUID, DATE)
  TO authenticated;
