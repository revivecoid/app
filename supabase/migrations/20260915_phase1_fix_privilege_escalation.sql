-- ═══════════════════════════════════════════════════════════════════════════════
-- PHASE 1 REMEDIATION: Privilege Escalation & Auth Bypass
-- Fixes: SEC-01, SEC-02, SEC-06, SEC-07
-- Audit: revive.co.id code review · 10 September 2026
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. HELPER: is_master_admin() — single source of truth for admin checks.
--    Reads from profiles.role (set only by service_role), NOT from JWT metadata.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_master_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'master_admin'
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0b. HELPER: is_partner_for(partner_uuid) — checks partner ownership via
--     app_metadata (set only by service_role via approve-partner).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_partner_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-07: Replace session_replication_role = 'replica' with explicit flag
-- ═══════════════════════════════════════════════════════════════════════════════

-- Modify the notification trigger to check a custom flag instead of relying
-- on session_replication_role being 'replica' (which disables ALL triggers).

CREATE OR REPLACE FUNCTION public.handle_job_status_change()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key  TEXT;
  payload           JSONB;
  request_id        BIGINT;
  skip_flag         TEXT;
BEGIN
  -- SEC-07: Check custom flag — admin RPCs set this to skip webhook
  BEGIN
    skip_flag := current_setting('app.skip_webhook', true);
  EXCEPTION WHEN OTHERS THEN
    skip_flag := 'off';
  END;

  IF skip_flag = 'on' THEN
    RETURN NEW;
  END IF;

  -- Only trigger if the status has actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN

    -- Read credentials from Supabase Vault / app.settings
    edge_function_url := current_setting('app.supabase_url', true)
                          || '/functions/v1/send-notification';
    service_role_key  := current_setting('app.service_role_key', true);

    -- If credentials not configured, skip webhook silently
    IF edge_function_url IS NULL OR service_role_key IS NULL
      OR edge_function_url = '/functions/v1/send-notification' THEN
      RETURN NEW;
    END IF;

    payload := jsonb_build_object(
      'job_id',      NEW.id,
      'customer_id', NEW.customer_id,
      'old_status',  OLD.status,
      'new_status',  NEW.status
    );

    -- net.http_post: body must be TEXT (cast jsonb → text)
    BEGIN
      SELECT net.http_post(
        url     := edge_function_url,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || service_role_key
        )::jsonb,
        body    := payload::text
      ) INTO request_id;
    EXCEPTION WHEN others THEN
      -- Webhook failure must never block the job update
      RAISE WARNING 'handle_job_status_change: webhook error (non-fatal): %', SQLERRM;
    END;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public, pg_temp;

-- Re-create the trigger
DROP TRIGGER IF EXISTS on_repair_job_status_change ON public.repair_jobs;
CREATE TRIGGER on_repair_job_status_change
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_job_status_change();


-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-01: Add role guard to admin RPCs
-- SEC-07: Replace session_replication_role with app.skip_webhook flag
-- ═══════════════════════════════════════════════════════════════════════════════

-- Revoke broad grants first
REVOKE EXECUTE ON FUNCTION public.admin_assign_job(UUID, UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_unassign_job(UUID) FROM authenticated;

CREATE OR REPLACE FUNCTION public.admin_assign_job(
  p_job_id    UUID,
  p_partner_id UUID,
  p_status    TEXT DEFAULT '3_booked'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- SEC-01: Role guard — only master_admin can call this
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  -- Validate status is a legal value
  IF p_status NOT IN ('1_intake','2_estimated','3_booked','4_paid','5_admitted',
                       '6_in_progress','7_finished','8_awaiting_delivery','9_done') THEN
    RAISE EXCEPTION 'invalid status value: %', p_status;
  END IF;

  -- SEC-07: Set custom flag to skip webhook trigger (instead of disabling ALL triggers)
  SET LOCAL app.skip_webhook = 'on';

  UPDATE public.repair_jobs
     SET partner_id = p_partner_id,
         status     = p_status
   WHERE id = p_job_id;
END;
$$;

-- Re-grant to authenticated (guard is in-body)
GRANT EXECUTE ON FUNCTION public.admin_assign_job(UUID, UUID, TEXT)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_unassign_job(
  p_job_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- SEC-01: Role guard — only master_admin can call this
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  -- SEC-07: Set custom flag to skip webhook trigger
  SET LOCAL app.skip_webhook = 'on';

  UPDATE public.repair_jobs
     SET partner_id = NULL,
         status     = '2_estimated'
   WHERE id = p_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_unassign_job(UUID)
  TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-02: Purge user_metadata role checks from ALL RLS policies
-- Replace with is_master_admin() helper that reads from profiles.role
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── profiles policies ────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Master Admins can read all profiles" ON public.profiles;
CREATE POLICY "Master Admins can read all profiles" ON public.profiles
    FOR SELECT TO authenticated
    USING (public.is_master_admin() OR auth.uid() = id);

-- Users can update their own profile (non-role fields)
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Users can insert their own profile (on signup)
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

-- ── partners policies ────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Master Admins can read all partners" ON public.partners;
CREATE POLICY "Master Admins can read all partners" ON public.partners
    FOR SELECT TO authenticated
    USING (public.is_master_admin() OR public.get_my_partner_id() = id);

DROP POLICY IF EXISTS "Master Admins can update all partners" ON public.partners;
CREATE POLICY "Master Admins can update all partners" ON public.partners
    FOR UPDATE TO authenticated
    USING (public.is_master_admin() OR public.get_my_partner_id() = id)
    WITH CHECK (public.is_master_admin() OR public.get_my_partner_id() = id);

DROP POLICY IF EXISTS "Master Admins can delete all partners" ON public.partners;
CREATE POLICY "Master Admins can delete all partners" ON public.partners
    FOR DELETE TO authenticated
    USING (public.is_master_admin());

-- ── partner_applications policies ────────────────────────────────────────────

DROP POLICY IF EXISTS "Enable insert for anyone" ON public.partner_applications;
CREATE POLICY "Enable insert for anyone" ON public.partner_applications
    FOR INSERT
    WITH CHECK (true);  -- SEC-12 will add captcha later; keep for now

DROP POLICY IF EXISTS "Enable read for master_admin" ON public.partner_applications;
CREATE POLICY "Enable read for master_admin" ON public.partner_applications
    FOR SELECT TO authenticated
    USING (public.is_master_admin());

DROP POLICY IF EXISTS "Enable update for master_admin" ON public.partner_applications;
CREATE POLICY "Enable update for master_admin" ON public.partner_applications
    FOR UPDATE TO authenticated
    USING (public.is_master_admin())
    WITH CHECK (public.is_master_admin());

-- ── partner_messages policies ────────────────────────────────────────────────

DROP POLICY IF EXISTS "Master Admins can read all partner messages" ON public.partner_messages;
CREATE POLICY "Master Admins can read all partner messages" ON public.partner_messages
    FOR SELECT TO authenticated
    USING (public.is_master_admin());

DROP POLICY IF EXISTS "Master Admins can insert partner messages" ON public.partner_messages;
CREATE POLICY "Master Admins can insert partner messages" ON public.partner_messages
    FOR INSERT TO authenticated
    WITH CHECK (public.is_master_admin());

DROP POLICY IF EXISTS "Partners can read their own messages" ON public.partner_messages;
CREATE POLICY "Partners can read their own messages" ON public.partner_messages
    FOR SELECT TO authenticated
    USING (
      public.get_my_partner_id() = partner_id
    );

DROP POLICY IF EXISTS "Partners can insert their own messages" ON public.partner_messages;
CREATE POLICY "Partners can insert their own messages" ON public.partner_messages
    FOR INSERT TO authenticated
    WITH CHECK (
      public.get_my_partner_id() = partner_id
      AND auth.uid() = sender_id
    );

-- Partner messages: allow marking as read
DROP POLICY IF EXISTS "Partners can update their own messages" ON public.partner_messages;
CREATE POLICY "Partners can update their own messages" ON public.partner_messages
    FOR UPDATE TO authenticated
    USING (public.get_my_partner_id() = partner_id)
    WITH CHECK (public.get_my_partner_id() = partner_id);


-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-06: Add missing RLS policies for core tables
-- These tables had RLS enabled but ZERO policies in the repo
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── vehicles policies ────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Users can manage own vehicles" ON public.vehicles;
CREATE POLICY "Users can manage own vehicles" ON public.vehicles
    FOR ALL TO authenticated
    USING (auth.uid() = customer_id)
    WITH CHECK (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Admin can read all vehicles" ON public.vehicles;
CREATE POLICY "Admin can read all vehicles" ON public.vehicles
    FOR SELECT TO authenticated
    USING (public.is_master_admin());

-- ── repair_jobs policies ─────────────────────────────────────────────────────

-- Drop any existing policies first (some may have been added outside repo)
DROP POLICY IF EXISTS "Customers can view own jobs" ON public.repair_jobs;
CREATE POLICY "Customers can view own jobs" ON public.repair_jobs
    FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

DROP POLICY IF EXISTS "Partners can view assigned jobs" ON public.repair_jobs;
CREATE POLICY "Partners can view assigned jobs" ON public.repair_jobs
    FOR SELECT TO authenticated
    USING (public.get_my_partner_id() = partner_id);

DROP POLICY IF EXISTS "Admin can manage all jobs" ON public.repair_jobs;
CREATE POLICY "Admin can manage all jobs" ON public.repair_jobs
    FOR ALL TO authenticated
    USING (public.is_master_admin())
    WITH CHECK (public.is_master_admin());

-- Customers can create jobs (estimator flow)
DROP POLICY IF EXISTS "Customers can create jobs" ON public.repair_jobs;
CREATE POLICY "Customers can create jobs" ON public.repair_jobs
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = customer_id);

-- Customers can update their own jobs (booking flow — status 2→3)
DROP POLICY IF EXISTS "Customers can update own jobs" ON public.repair_jobs;
CREATE POLICY "Customers can update own jobs" ON public.repair_jobs
    FOR UPDATE TO authenticated
    USING (auth.uid() = customer_id)
    WITH CHECK (auth.uid() = customer_id);

-- Partners can update assigned jobs (status advancement)
DROP POLICY IF EXISTS "Partners can update assigned jobs" ON public.repair_jobs;
CREATE POLICY "Partners can update assigned jobs" ON public.repair_jobs
    FOR UPDATE TO authenticated
    USING (public.get_my_partner_id() = partner_id)
    WITH CHECK (public.get_my_partner_id() = partner_id);

-- ── repair_photos policies ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "Users can view photos for own jobs" ON public.repair_photos;
CREATE POLICY "Users can view photos for own jobs" ON public.repair_photos
    FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.repair_jobs
        WHERE repair_jobs.id = repair_photos.job_id
          AND (repair_jobs.customer_id = auth.uid()
               OR repair_jobs.partner_id = public.get_my_partner_id()
               OR public.is_master_admin())
      )
    );

DROP POLICY IF EXISTS "Authenticated can insert photos" ON public.repair_photos;
CREATE POLICY "Authenticated can insert photos" ON public.repair_photos
    FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS (
        SELECT 1 FROM public.repair_jobs
        WHERE repair_jobs.id = repair_photos.job_id
          AND (repair_jobs.customer_id = auth.uid()
               OR repair_jobs.partner_id = public.get_my_partner_id()
               OR public.is_master_admin())
      )
    );

-- ── ai_training_context policies ─────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin can manage ai_training_context" ON public.ai_training_context;
CREATE POLICY "Admin can manage ai_training_context" ON public.ai_training_context
    FOR ALL TO authenticated
    USING (public.is_master_admin())
    WITH CHECK (public.is_master_admin());
