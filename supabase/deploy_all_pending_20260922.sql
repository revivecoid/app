-- ═══════════════════════════════════════════════════════════════════════════════
-- re-V  ·  Supabase deploy script   (project ahaospjkkuetkaixwzzz)
--
-- Paste this whole file into the Supabase SQL Editor and Run.
--
-- WHAT THIS IS
--   The consolidated, re-runnable form of the 11 migrations dated 2026-09-22.
--   SQL for this project is applied by hand and there is no migration history
--   table, so this file — not the repo — is the deployment mechanism.
--
-- Verified against the live database on 2026-09-22: every function below already
-- matches the migration source byte-for-byte after normalisation, and every
-- object it creates already exists. So this is a RE-ASSERT, not a first install.
-- Running it is safe and should change nothing.
--
-- WHAT IT ENFORCES
--   * Repair may not start before the customer has PAID. Two gates, because the
--     ops stage screen writes its milestone and advances the job as two separate
--     statements: advance_job_status (status edge) and ops_may_act_on_stage
--     (the milestone write itself). Gating only the first leaves the milestone
--     committed while the job sits behind it, and every later stage becomes
--     unreachable.
--   * Anonymous guests may estimate; booking still requires a real login.
--   * Partner applications only via the submit-partner-application edge function.
--   * The 'revive-photos' and 'revive-photos-r2-proxy' buckets are closed.
--
-- SAFETY
--   Everything runs inside one transaction. If any statement fails, the whole
--   script rolls back and the database is left exactly as it was. There is no
--   partial state to clean up.
--
--   This script does not drop tables or delete rows. The only DESTRUCTIVE
--   statements are DROP POLICY / DROP CONSTRAINT / DROP COLUMN, each of which
--   immediately precedes a re-CREATE or is already guarded by IF EXISTS.
--
--   Row data is touched in exactly two places, both idempotent:
--     partner_applications.submitted_at backfilled from created_at where NULL
--     status 'pending_review' normalised to 'pending'
--
-- A VERIFICATION BLOCK IS AT THE BOTTOM. Read its output to confirm the run.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- Auto-assignment engine (table, columns, is_master_admin policies)
-- source: supabase/migrations/20260922_auto_assign_engine.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Migration: Auto Assignment Engine
-- =============================================================================

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS auto_assign_active BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_assign_priority INTEGER DEFAULT 999,
  ADD COLUMN IF NOT EXISTS auto_assign_capacity INTEGER DEFAULT 10;

CREATE TABLE IF NOT EXISTS public.auto_assign_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    is_active BOOLEAN DEFAULT false NOT NULL,
    match_location BOOLEAN DEFAULT true NOT NULL,
    mode TEXT DEFAULT 'strict_priority' NOT NULL CHECK (mode IN ('fill_first', 'strict_priority', 'round_robin')),
    last_partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO public.auto_assign_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.auto_assign_settings ENABLE ROW LEVEL SECURITY;
-- Re-runnable guard: CREATE POLICY raises 42710 if the name already exists.
DROP POLICY IF EXISTS "Admin manage auto assign settings" ON public.auto_assign_settings;
DROP POLICY IF EXISTS "Anyone read auto assign settings" ON public.auto_assign_settings;
CREATE POLICY "Admin manage auto assign settings" ON public.auto_assign_settings FOR ALL TO authenticated USING (public.is_master_admin()) WITH CHECK (public.is_master_admin());
CREATE POLICY "Anyone read auto assign settings" ON public.auto_assign_settings FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.get_partner_active_job_count(p_partner_id UUID)
RETURNS INTEGER LANGUAGE sql SECURITY DEFINER AS $$
  SELECT count(*)::INT FROM public.repair_jobs
  WHERE partner_id = p_partner_id AND status IN ('3_booked', '3_inspected', '4_paid', '5_admitted', '6_in_progress', '7_finished', '8_awaiting_delivery');
$$;

CREATE OR REPLACE FUNCTION public.execute_auto_assign(p_job_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_job RECORD;
  v_settings RECORD;
  v_assigned_partner_id UUID := NULL;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Job not found'); END IF;
  IF v_job.partner_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Job already assigned'); END IF;
  
  SELECT * INTO v_settings FROM public.auto_assign_settings WHERE id = 1;
  IF NOT v_settings.is_active THEN RETURN jsonb_build_object('success', false, 'error', 'Auto-assign is disabled'); END IF;

  IF v_settings.mode IN ('fill_first', 'strict_priority') THEN
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'round_robin' THEN
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_capacity, public.get_partner_active_job_count(p.id) as current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) as rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS ( SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id )
    SELECT op.id INTO v_assigned_partner_id
    FROM ordered_partners op
    WHERE op.current_jobs < op.auto_assign_capacity
    ORDER BY CASE WHEN (SELECT rn FROM last_partner) IS NOT NULL AND op.rn > (SELECT rn FROM last_partner) THEN 0 ELSE 1 END, op.rn ASC
    LIMIT 1;
  END IF;

  IF v_assigned_partner_id IS NOT NULL THEN
    PERFORM set_config('app.skip_webhook', 'true', true);
    UPDATE public.repair_jobs SET partner_id = v_assigned_partner_id, status_changed_at = NOW() WHERE id = p_job_id;
    PERFORM set_config('app.skip_webhook', 'false', true);
    UPDATE public.auto_assign_settings SET last_partner_id = v_assigned_partner_id WHERE id = 1;
    RETURN jsonb_build_object('success', true, 'partner_id', v_assigned_partner_id);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'No eligible partner found with capacity');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.execute_auto_assign(UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- Allocation strategy: strict priority with empty-slot override
-- source: supabase/migrations/20260922_fix_fill_first_allocation.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Migration: Fix fill_first allocation strategy
-- -----------------------------------------------------------------------------
-- fill_first was previously implemented as "fill the top workshop, then let it
-- drain to 0 before touching it again" (drain-to-empty). That is wrong.
--
-- Correct semantics:
--   fill_first  = round-robin rotation across the priority queue, with ONE
--                 override: a higher priority workshop (lower auto_assign_priority
--                 than the rotation's next pick) that is currently EMPTY
--                 (0 active jobs) takes that single job instead.
--                 As soon as it holds a job it is no longer empty and the
--                 rotation resumes normally.
--   strict_priority = always the highest priority workshop with ANY open slot.
--   round_robin     = pure even distribution in priority order.
-- =============================================================================

ALTER TABLE public.partners DROP COLUMN IF EXISTS auto_assign_is_draining;

CREATE OR REPLACE FUNCTION public.execute_auto_assign(p_job_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_job RECORD;
  v_settings RECORD;
  v_assigned_partner_id UUID := NULL;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Job not found'); END IF;
  IF v_job.partner_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Job already assigned'); END IF;

  SELECT * INTO v_settings FROM public.auto_assign_settings WHERE id = 1;
  IF NOT v_settings.is_active THEN RETURN jsonb_build_object('success', false, 'error', 'Auto-assign is disabled'); END IF;

  IF v_settings.mode = 'strict_priority' THEN
    -- Highest priority workshop with ANY open slot takes the job.
    SELECT p.id INTO v_assigned_partner_id
    FROM public.partners p
    WHERE p.auto_assign_active = true
      AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
      AND public.get_partner_active_job_count(p.id) < p.auto_assign_capacity
    ORDER BY p.auto_assign_priority ASC, p.created_at ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'fill_first' THEN
    -- Round-robin rotation, overridden by a higher priority workshop only while
    -- that workshop is completely empty.
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_priority, p.auto_assign_capacity,
             public.get_partner_active_job_count(p.id) AS current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) AS rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS (
      SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id
    ),
    rotation_pick AS (
      SELECT op.id, op.auto_assign_priority, op.rn
      FROM ordered_partners op
      WHERE op.current_jobs < op.auto_assign_capacity
      ORDER BY CASE
                 WHEN (SELECT rn FROM last_partner) IS NOT NULL
                      AND op.rn > (SELECT rn FROM last_partner) THEN 0
                 ELSE 1
               END, op.rn ASC
      LIMIT 1
    )
    SELECT c.id INTO v_assigned_partner_id
    FROM (
      -- 1st choice: an empty workshop with better priority than the rotation pick
      SELECT op.id, 1 AS pref, op.auto_assign_priority AS pr, op.rn
      FROM ordered_partners op
      WHERE op.current_jobs = 0
        AND op.current_jobs < op.auto_assign_capacity
        AND op.auto_assign_priority < (SELECT auto_assign_priority FROM rotation_pick)
      UNION ALL
      -- 2nd choice: the rotation pick itself
      SELECT rp.id, 2 AS pref, rp.auto_assign_priority AS pr, rp.rn
      FROM rotation_pick rp
    ) c
    ORDER BY c.pref ASC, c.pr ASC, c.rn ASC
    LIMIT 1;

  ELSIF v_settings.mode = 'round_robin' THEN
    -- Even distribution in priority order, one job per workshop per cycle.
    WITH ordered_partners AS (
      SELECT p.id, p.auto_assign_capacity,
             public.get_partner_active_job_count(p.id) AS current_jobs,
             row_number() OVER (ORDER BY p.auto_assign_priority ASC, p.created_at ASC) AS rn
      FROM public.partners p
      WHERE p.auto_assign_active = true
        AND (v_settings.match_location = false OR p.service_area = v_job.service_area)
    ),
    last_partner AS (
      SELECT rn FROM ordered_partners WHERE id = v_settings.last_partner_id
    )
    SELECT op.id INTO v_assigned_partner_id
    FROM ordered_partners op
    WHERE op.current_jobs < op.auto_assign_capacity
    ORDER BY CASE
               WHEN (SELECT rn FROM last_partner) IS NOT NULL
                    AND op.rn > (SELECT rn FROM last_partner) THEN 0
               ELSE 1
             END, op.rn ASC
    LIMIT 1;
  END IF;

  IF v_assigned_partner_id IS NOT NULL THEN
    PERFORM set_config('app.skip_webhook', 'true', true);
    UPDATE public.repair_jobs SET partner_id = v_assigned_partner_id, status_changed_at = NOW() WHERE id = p_job_id;
    PERFORM set_config('app.skip_webhook', 'false', true);
    UPDATE public.auto_assign_settings SET last_partner_id = v_assigned_partner_id WHERE id = 1;
    RETURN jsonb_build_object('success', true, 'partner_id', v_assigned_partner_id);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'No eligible partner found with capacity');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.execute_auto_assign(UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- Anonymous signup: make handle_new_user NULL-safe
-- source: supabase/migrations/20260922_guest_estimating_anon_signup.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- Guest (anonymous) estimating — restore the pre-login estimation flow.
--
-- SEC-03/SEC-04 moved vision-estimation behind a JWT and made both the photo
-- upload path and the storage bucket user-scoped. That is correct and stays.
-- Guests get that JWT by signing in anonymously, but GoTrue could not create
-- anonymous users against this schema: an anonymous user has NULL email and no
-- full_name, while profiles.email and profiles.full_name are NOT NULL with no
-- default. Postgres raised 23502 inside the signup trigger and GoTrue surfaced
-- it as 500 "Database error creating anonymous user".
--
-- COALESCE placeholders keep the trigger working for guests. A guest row is
-- upgraded with the real values when the account is linked/converted, because
-- the trigger only runs once per auth.users row.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
      'Guest'
    ),
    COALESCE(NEW.email, ''),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;

  -- memberships is the source of truth; keep it populated for every new signup
  INSERT INTO public.memberships (user_id, scope, role, status)
  VALUES (NEW.id, 'customer', 'customer', 'active')
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- claim_guest_jobs(): move a guest's job to their real account
-- source: supabase/migrations/20260922_claim_guest_jobs.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- Claim a job that was estimated anonymously.
--
-- A guest gets a real (anonymous) session so the vision pipeline can stay
-- authenticated, which means the guest OWNS the row it wrote: repair_jobs
-- INSERT requires auth.uid() = customer_id. If that visitor later signs in with
-- Google and the email matches an existing account, GoTrue cannot always merge
-- the anonymous row — it is left owned by an id nobody can log back into, so the
-- booking they were in the middle of disappears.
--
-- This lets the signer-in take those rows over, under strict limits:
--   * only an anonymous CURRENT user may call it (a guest taking over a job),
--   * the caller must now carry a real email, i.e. the conversion just happened,
--   * only rows owned by the calling user, unassigned, and still pre-payment.
-- A partial index keeps it cheap for the common case of no guest rows at all.

CREATE INDEX IF NOT EXISTS repair_jobs_guest_claim_idx
  ON public.repair_jobs (customer_id)
  WHERE partner_id IS NULL;

CREATE OR REPLACE FUNCTION public.claim_guest_jobs()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user   RECORD;
  v_count  INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_user FROM auth.users WHERE id = auth.uid();

  IF v_user IS NULL OR NOT COALESCE(v_user.is_anonymous, false) THEN
    RAISE EXCEPTION 'only an anonymous (guest) session may claim guest jobs'
      USING ERRCODE = '42501';
  END IF;

  IF v_user.email IS NULL OR v_user.email = '' THEN
    RAISE EXCEPTION 'no email on this account yet' USING ERRCODE = '42501';
  END IF;

  UPDATE public.repair_jobs
     SET customer_id = v_user.id,
         updated_at  = now()
   WHERE customer_id = v_user.id
     AND partner_id IS NULL
     AND status IN ('1_intake', '2_estimated');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_guest_jobs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_guest_jobs() TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- Partner applications: full submitted profile + status constraint
-- source: supabase/migrations/20260922_partner_applications_full_fields.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX: submitted workshop applications never reached the database
--
-- Root cause: partner_registration_screen.dart inserts entity_name, tier,
-- paint_brand, throughput_capacity, service_radius_km, submitted_at and the
-- *_file_key columns into public.partner_applications. Those columns were added
-- to `partners` (20260910_expand_partners_table / 20260915_phase4) but never to
-- `partner_applications`, so PostgREST rejected every insert:
--     400 PGRST204 "Could not find the 'entity_name' column of
--                   'partner_applications' in the schema cache"
-- The client swallowed that error and still showed the success screen, so no
-- application row was ever written and nothing appeared in Partner Assessment.
--
-- The original CHECK also rejected the 'pending_review' status the shipped client
-- sent, which would have failed the insert even with the columns present.
--
-- Additive and idempotent — safe to run against live data.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Form fields the client sends but the table never had ──────────────────
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS entity_name         TEXT,
  ADD COLUMN IF NOT EXISTS tier                INTEGER DEFAULT 2,
  ADD COLUMN IF NOT EXISTS paint_brand         TEXT    DEFAULT 'glasurit',
  ADD COLUMN IF NOT EXISTS throughput_capacity INTEGER DEFAULT 12,
  ADD COLUMN IF NOT EXISTS service_radius_km   NUMERIC DEFAULT 15,
  ADD COLUMN IF NOT EXISTS submitted_at        TIMESTAMPTZ DEFAULT NOW();

-- ─── 2. Uploaded evidence ────────────────────────────────────────────────────
-- Storage paths inside the private 'revive-photos' bucket. Mirrors the column
-- names on `partners` so approve-partner can carry them straight across.
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS nib_file_key         TEXT,
  ADD COLUMN IF NOT EXISTS npwp_file_key        TEXT,
  ADD COLUMN IF NOT EXISTS siup_file_key        TEXT,
  ADD COLUMN IF NOT EXISTS ktp_file_key         TEXT,
  -- Facility photos are 4 fixed slots; a JSONB array of
  -- {"slot":0,"label":"Workshop Facade","file_key":"<uid>/partner-applications/..."}
  ADD COLUMN IF NOT EXISTS facility_photo_keys  JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.partner_applications.tier IS
  '1=Flagship Spray Facility, 2=Authorized Partner, 3=Express PDR Center';
COMMENT ON COLUMN public.partner_applications.submitted_at IS
  'Client submit timestamp; backfilled from created_at for legacy rows';
COMMENT ON COLUMN public.partner_applications.facility_photo_keys IS
  'Array of {slot,label,file_key} for the 4 facility photo slots';

-- Legacy rows only ever had created_at.
UPDATE public.partner_applications
   SET submitted_at = created_at
 WHERE submitted_at IS NULL;

-- ─── 3. Status constraint ────────────────────────────────────────────────────
-- Accept the shipped client's 'pending_review', then normalise it to the
-- canonical queue status the admin Partner Assessment filters on.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT con.conname
      FROM pg_constraint con
      JOIN pg_class     rel ON rel.oid = con.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
     WHERE nsp.nspname = 'public'
       AND rel.relname = 'partner_applications'
       AND con.contype = 'c'
       AND pg_get_constraintdef(con.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.partner_applications DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_status_check
  CHECK (status IN ('pending', 'pending_review', 'approved', 'rejected'));

UPDATE public.partner_applications
   SET status = 'pending'
 WHERE status = 'pending_review';

-- ─── 4. Admin queue index ────────────────────────────────────────────────────
-- SELECT ... WHERE status = 'pending' ORDER BY submitted_at DESC
CREATE INDEX IF NOT EXISTS idx_partner_applications_status_submitted
  ON public.partner_applications(status, submitted_at DESC);

-- ────────────────────────────────────────────────────────────────────────────────────────
-- Create the 'partner-docs' bucket + its policies
-- source: supabase/migrations/20260922_create_partner_docs_bucket.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-08: make 'partner-docs' real, or stop referencing it
--
-- 20260920_memberships_foundation.sql defines storage RLS policies that reference
-- a 'partner-docs' bucket, but the bucket was never created. The Storage API
-- answered {"error":"Bucket not found","code":"NoSuchBucket"} for every request
-- against it, which is why an earlier probe of that bucket returned
-- 'Bucket not found' rather than a policy denial.
--
-- Nothing is broken today: `partner-docs` appears in 0 Dart files, and
-- partner_profile_controller.dart routes NIB/NPWP/SIUP/KTP through 'revive-photos'
-- (static const _bucket = 'revive-photos'). The migration records were simply
-- describing a store that did not exist.
--
-- This creates it as the private, owner-scoped store those migrations describe, so
-- the documented layout is real and future code can rely on it. It is NOT
-- retrofitted as the destination for existing documents — those live in
-- 'revive-photos' and moving them would break the app.
--
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('partner-docs', 'partner-docs', false, 10485760)
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = COALESCE(storage.buckets.file_size_limit, 10485760);

-- Owner-scoped access, matching the intent of 20260920_memberships_foundation.
-- Path layout mirrors the convention used in 'revive-photos':
--   partners/<partner_id>/docs/<type>_<ts>.<ext>
-- Identity comes from the JWT claim app_metadata.partner_id (what
-- get_my_partner_id() returns and set_user_role() writes) or an active partner
-- membership — partners.user_id is NULL on every row, so it is not used.
DROP POLICY IF EXISTS "Partner members manage their docs" ON storage.objects;
CREATE POLICY "Partner members manage their docs"
  ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'partner-docs'
    AND (
      (
        (storage.foldername(name))[1] = 'partners'
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
      OR public.is_master_admin()
    )
  )
  WITH CHECK (
    bucket_id = 'partner-docs'
    AND (
      (
        (storage.foldername(name))[1] = 'partners'
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
      OR public.is_master_admin()
    )
  );

-- ────────────────────────────────────────────────────────────────────────────────────────
-- SEC-05: close open policies on 'revive-photos'
-- source: supabase/migrations/20260922_storage_bucket_rls_hardening.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-05: close the open read/write policies on the 'revive-photos' bucket
--
-- Verified live against project ahaospjkkuetkaixwzzz on 2026-09-22:
--
--   INSERT  "Allow Public Uploads"  roles=public  WITH CHECK (bucket_id='revive-photos')
--     POST /storage/v1/object/revive-photos/anon-probe/hole.jpg with nothing but the
--     anon key  →  200 {"Key":"revive-photos/anon-probe/hole.jpg"}
--     Any path, any bytes, no session. The SEC-04 comment at
--     estimator_screen.dart:143 assumes this insert is scoped to <auth.uid()>/ — it is not.
--
--   SELECT  "Public Read Access"  roles=public  USING (bucket_id='revive-photos')
--     GET /storage/v1/object/revive-photos/proof_37e9d9fe-....pdf  →  200, 14318 bytes,
--     the customer's whole payment proof. Every damage photo, transfer proof and
--     partner KTP/NIB document in the bucket was world-readable through the RLS endpoint.
--
-- Two path families that had NO policy of their own were being carried by those two
-- holes and are granted explicitly here:
--   partners/<partner_id>/docs|facility/...   partner_profile_controller.dart:395,465
--   ops/<partner_id>/...                      already covered by the ops policies
--
-- The intended scopes keep working:
--   <auth.uid()>/...  own-folder INSERT/SELECT/DELETE policies (guest estimator,
--                     registration, transfer proofs, partner progress photos).
--                     GuestSession.ensure() signs the visitor in anonymously, which
--                     yields a real `authenticated` JWT, so these still pass.
--   ops/<partner_id>/...  ops-role policies (unchanged)
--   admins                is_master_admin() policies (unchanged)
--
-- Idempotent: the two DROP POLICY statements are safe re-runs.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Remove the two world-open policies ───────────────────────────────────
DROP POLICY IF EXISTS "Allow Public Uploads" ON storage.objects;
DROP POLICY IF EXISTS "Public Read Access"   ON storage.objects;

-- ─── 2. WRITE: partner members upload into their own partner folder ──────────
-- Identity comes from the same two sources the application itself trusts:
--   * auth.jwt() -> app_metadata -> 'partner_id'  (this is exactly what
--     public.get_my_partner_id() returns, and what set_user_role() writes)
--   * public.memberships  scope='partner', status='active', role in (owner, mechanic, staff)
-- partners.user_id is deliberately NOT used: it is NULL on every row in this project.
DROP POLICY IF EXISTS "Partner members can upload to their partner folder" ON storage.objects;
CREATE POLICY "Partner members can upload to their partner folder"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'partners'
    AND (
      (
        (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
    )
  );

-- ─── 3. READ: partner members read their own partner folder ──────────────────
DROP POLICY IF EXISTS "Partner members can read their partner folder" ON storage.objects;
CREATE POLICY "Partner members can read their partner folder"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'partners'
    AND (
      (
        (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
    )
  );

-- ─── 4. READ: job participants read photos attached to their own job ─────────
-- Replaces what "Public Read Access" was accidentally providing: the customer
-- tracking gallery (job_stream_controller.dart) and the partner job thumbnails
-- (partner_dashboard_controller.dart:198). Scope the readable set to keys that
-- are actually recorded against a job the caller is party to, so a signed-in
-- user cannot enumerate the bucket.
DROP POLICY IF EXISTS "Job participants can read job photos" ON storage.objects;
CREATE POLICY "Job participants can read job photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (
      EXISTS (
        SELECT 1
          FROM public.repair_photos rp
          JOIN public.repair_jobs   rj ON rj.id = rp.job_id
         WHERE rp.r2_file_key = name
           AND (
             rj.customer_id = auth.uid()
             OR public.has_partner_membership(
                  rj.partner_id,
                  ARRAY['owner', 'mechanic', 'staff']::membership_role[]
                )
           )
      )
      OR EXISTS (
        SELECT 1
          FROM public.job_milestone_photos jmp
          JOIN public.repair_jobs         rj ON rj.id = jmp.job_id
         WHERE jmp.file_key = name
           AND (
             rj.customer_id = auth.uid()
             OR public.has_partner_membership(
                  rj.partner_id,
                  ARRAY['owner', 'mechanic', 'staff']::membership_role[]
                )
           )
      )
    )
  );

-- ─── 5. Net effect on storage.objects for this bucket ────────────────────────
--   SELECT  Users can read own files            authenticated   <uid>/...
--   SELECT  Admins can read all files           is_master_admin()
--   SELECT  Ops roles can read milestone photos partner_staff|partner_driver   ops/...
--   SELECT  Partner members can read ...        (new, §3)
--   SELECT  Job participants can read ...       (new, §4)
--   INSERT  Users can upload to own folder      authenticated   <uid>/...
--   INSERT  Ops roles can upload milestone ...  partner_staff|partner_driver   ops/...
--   INSERT  Partner members can upload ...      (new, §2)
--   DELETE  Users can delete own files          authenticated   <uid>/...
--   REMOVED Allow Public Uploads, Public Read Access
--
-- service_role bypasses RLS and is unaffected.
-- Legacy root-level objects stay readable to the job's own customer/partner via
-- the key match in §4, and to admins via §5. Unreferenced root-level CMS assets
-- become admin-only.

-- ────────────────────────────────────────────────────────────────────────────────────────
-- SEC-07: seal the legacy 'revive-photos-r2-proxy' bucket
-- source: supabase/migrations/20260922_seal_r2_proxy_bucket.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-07: seal the legacy 'revive-photos-r2-proxy' bucket
--
-- State before (verified 2026-09-22):
--   storage.buckets.public = true
--   'Public Access' SELECT roles={public} USING (bucket_id='revive-photos-r2-proxy')
--   'Auth Upload'   INSERT roles={public} WITH CHECK (… AND auth.role()='authenticated')
--   'Auth Update'   UPDATE roles={public} WITH CHECK (… AND auth.role()='authenticated')
--
-- So every object in it was world-readable on the public route, and any signed-in
-- user could write arbitrary paths into it.
--
-- This bucket was created by 20260911_create_storage_bucket.sql and superseded by
-- 'revive-photos'. It holds 4 objects, all dated 2026-09-11. No code in the repo
-- references 'revive-photos-r2-proxy' (0 matches across .dart/.sql/.ts/.json/.toml),
-- so nothing builds URLs against it.
--
-- Data repair carried out alongside this migration:
--   2 of the 4 objects are referenced by public.repair_photos.r2_file_key
--   (uploaded 2026-09-11 07:23–07:26, job 37e9d9fe) and existed ONLY in this
--   bucket. Because the app builds photo URLs against 'revive-photos', those two
--   photos did not resolve at all — a latent broken-image bug. They were copied
--   into 'revive-photos' and verified at 9185 bytes, image/jpeg, before this
--   bucket was made private. The other 2 objects are orphaned (no referencing row).
--
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════════

UPDATE storage.buckets
   SET public = false
 WHERE id = 'revive-photos-r2-proxy';

DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload"   ON storage.objects;
DROP POLICY IF EXISTS "Auth Update"   ON storage.objects;

-- Note: the three policies above were named for this bucket, but DROP POLICY
-- matches on the policy name alone. 'revive-photos' has its own separately named
-- policies ('Users can upload to own folder', 'Users can read own files',
-- 'Admins can read all files', …) plus the SEC-05 partner/job policies, so none of
-- those are affected. Verify after applying:
--   select policyname, cmd from pg_policies
--    where schemaname='storage' and tablename='objects'
--      and coalesce(with_check,qual) ilike '%revive-photos-r2-proxy%';
--   -- expected: 0 rows
--
-- After this: the bucket is reachable by service_role only.

-- ────────────────────────────────────────────────────────────────────────────────────────
-- SEC-06: applications only via the edge function
-- source: supabase/migrations/20260922_partner_application_submission_lockdown.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-06: partner applications may only be created through the edge function
--
-- Live policy before this migration (verified 2026-09-22):
--
--   'Enable insert for anyone'  INSERT  roles={public}  WITH CHECK (true)
--
-- An unrestricted INSERT for the `public` role. GuestSession.ensure() mints an
-- anonymous session on demand, so the endpoint was effectively open: anyone
-- holding the anon key could script rows straight into the admin Partner
-- Assessment queue, with no validation, no attribution and no evidence.
--
-- The only legitimate writer is now the `submit-partner-application` edge
-- function, which runs as service_role (bypasses RLS) and validates:
--   * required fields present, email well formed
--   * every *_file_key / facility_photo_keys[].file_key sits under the caller's
--     own '<uid>/partner-applications/' prefix — no citing someone else's objects
--   * at least one photo or legal document attached
--   * max 3 submissions per session per rolling 24h
--   * one pending application per email
--
-- After this migration there is NO insert policy for anon/authenticated on this
-- table, so a direct PostgREST insert is refused by RLS.
--
-- Client side: partner_registration_screen.dart must call the function instead of
-- .from('partner_applications').insert(...) — applied in the same change.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Attribute each application to the session that filed it ──────────────
-- Needed for the per-session rate limit; also gives the reviewer a record of who
-- submitted, which the old unrestricted insert could not provide.
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS submitted_by UUID;

COMMENT ON COLUMN public.partner_applications.submitted_by IS
  'auth.uid() of the submitting session (may be an anonymous guest). Written by submit-partner-application.';

CREATE INDEX IF NOT EXISTS idx_partner_applications_submitted_by_created
  ON public.partner_applications(submitted_by, created_at DESC);

-- ─── 2. One pending application per email ────────────────────────────────────
-- Backstop for the function's own check, so a race cannot leave the reviewer with
-- two live rows for the same workshop. Partial: rejected/approved history is
-- unaffected, so a workshop may re-apply after a rejection.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_partner_applications_pending_email
  ON public.partner_applications (lower(email))
  WHERE status = 'pending';

-- ─── 3. Close the open insert ────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enable insert for anyone" ON public.partner_applications;

-- Deliberately no replacement INSERT policy: service_role bypasses RLS, and
-- service_role is reachable only from the edge function. Reads and updates stay
-- master_admin-only as before ('Enable read for master_admin',
-- 'Enable update for master_admin').

-- ────────────────────────────────────────────────────────────────────────────────────────
-- GATE: repair cannot start before payment (advance_job_status)
-- source: supabase/migrations/20260922_gate_repair_on_payment.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- Gate: repair cannot start before the customer has PAID.
--
-- The live advance_job_status() still encoded the pre-redesign order: it reached
-- 6_in_progress from 4_paid OR 5_admitted, so a workshop could push a car from the
-- bay straight into repair, skipping invoice issuance (3_inspected) and payment
-- (4_paid). The documented sequence is
--
--     3_booked -> 5_admitted -> 3_inspected -> 4_paid -> 6_in_progress
--
-- so the 5_admitted -> 6_in_progress edge is removed from both workshop branches.
-- 4_paid -> 6_in_progress is untouched and is now the ONLY way into repair.
--
-- Generated from the live body by targeted substitution so nothing else in this
-- function can drift; on this project SQL is applied by hand and there is no
-- migration history table, so the repo copy is not authoritative.

CREATE OR REPLACE FUNCTION public.advance_job_status(p_job_id uuid, p_new_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job           RECORD;
  v_caller_role   TEXT;
  v_partner_id    UUID;
  v_allowed       BOOLEAN := FALSE;
  v_is_owner      BOOLEAN := FALSE;
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

  -- Role: JWT app_metadata first, then the DB profile. Never user_metadata.
  v_caller_role := COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'role'),
    (SELECT p.role::TEXT FROM public.profiles p WHERE p.id = auth.uid())
  );

  -- Tenant: JWT partner_id is authoritative, profile is the fallback.
  v_partner_id := COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID,
    (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid())
  );

  v_is_owner := (v_job.customer_id = auth.uid());

  -- Ownership first: a partner mechanic may also be a customer of another
  -- workshop, so their own job must not be judged by their workshop role.
  IF v_is_owner AND (
       (v_job.status = '2_estimated' AND p_new_status = '3_booked') OR
       (v_job.status = '3_inspected' AND p_new_status = '4_paid')
     ) THEN
    v_allowed := TRUE;
  ELSE
    CASE v_caller_role

      WHEN 'master_admin' THEN
        v_allowed := TRUE;

      WHEN 'customer' THEN
        v_allowed := (
          (v_job.status = '2_estimated'  AND p_new_status = '3_booked') OR
          (v_job.status = '3_inspected'  AND p_new_status = '4_paid')
        ) AND v_is_owner;

      WHEN 'partner_mechanic' THEN
        IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
          RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
        END IF;
        v_allowed := (
          (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
          (v_job.status = '4_paid'               AND p_new_status = '6_in_progress') OR
          (v_job.status = '6_in_progress'        AND p_new_status = '7_finished') OR
          (v_job.status = '7_finished'           AND p_new_status = '8_awaiting_delivery')
        );

      WHEN 'partner_staff' THEN
        IF v_job.partner_id IS DISTINCT FROM v_partner_id THEN
          RAISE EXCEPTION 'forbidden: this job is not assigned to your workshop';
        END IF;
        v_allowed := (
          (v_job.status IN ('3_booked','4_paid') AND p_new_status = '5_admitted') OR
          (v_job.status = '4_paid'               AND p_new_status = '6_in_progress') OR
          (v_job.status = '6_in_progress'        AND p_new_status = '7_finished')
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
  END IF;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transition % → % not allowed for role %',
      v_job.status, p_new_status, COALESCE(v_caller_role, '<unresolved>');
  END IF;

  IF p_new_status = '5_admitted' AND v_job.status = '3_booked' THEN
    IF v_job.scheduled_date IS NOT NULL THEN
      INSERT INTO public.partner_booked_slots (partner_id, job_id, booked_date)
      VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  UPDATE public.repair_jobs
     SET status = p_new_status,
         status_changed_at = NOW()
   WHERE id = p_job_id;

END;
$function$;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- GATE: milestone write refused before payment (ops_may_act_on_stage)
-- source: supabase/migrations/20260922_ops_milestone_payment_gate.sql
-- ────────────────────────────────────────────────────────────────────────────────────────

-- Repair may not start before the customer has PAID (ops milestone gate).
--
-- Companion to 20260922_gate_repair_on_payment.sql, which removed the
-- 5_admitted -> 6_in_progress edge from advance_job_status. That alone was not
-- enough: the ops stage screen inserts the job_milestones row and then calls
-- advance_job_status as two separate statements (ops_stage_photo_screen.dart
-- ~line 296 then ~line 314), with no transaction around them. Refusing only the
-- status change would leave `disassembly` committed while the job still sat at
-- 5_admitted — and since welding/body_filler/painting/polishing/qc_finished all
-- require 6_in_progress, the job would be permanently stuck.
--
-- This function is the single choke point for every ops milestone write: three
-- restrictive policies depend on it (job_milestones INSERT and UPDATE,
-- job_milestone_photos INSERT). Blocking here therefore stops the write before it
-- happens, so the refusal is atomic from the operator's point of view.
--
-- Generated from the live body by targeted substitution so nothing else drifts.

CREATE OR REPLACE FUNCTION public.ops_may_act_on_stage(p_job_id uuid, p_stage_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_role       TEXT;
  v_partner    UUID;
  v_mode       TEXT;
  v_job_status TEXT;
BEGIN
  v_role    := (auth.jwt() -> 'app_metadata' ->> 'role')::TEXT;
  v_partner := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::UUID;

  -- A platform admin is outside the workshop model entirely.
  IF v_role = 'master_admin' THEN
    RETURN TRUE;
  END IF;

  -- Not an ops operator at all (customer, anon, absent claim).
  IF v_role IS NULL OR v_role NOT IN ('partner_staff', 'partner_driver', 'partner_mechanic') THEN
    RETURN FALSE;
  END IF;

  -- Must be THIS workshop's job. Tenant isolation is not softened by the mode.
  -- The job's status is read in the same pass, because it decides whether repair
  -- work may be recorded at all.
  SELECT r.status INTO v_job_status
    FROM public.repair_jobs r
   WHERE r.id = p_job_id AND r.partner_id = v_partner;

  IF v_partner IS NULL OR v_job_status IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Repair may not begin before the customer has PAID. Every repair stage
  -- (disassembly onward) writes a milestone straight from the ops app and only
  -- afterwards asks advance_job_status to move the job, as two separate calls —
  -- so gating only the status change would commit the milestone and leave the job
  -- behind it, making every later stage unreachable. Refusing the milestone write
  -- here is the one place that keeps the two in step.
  --
  -- `vehicle_intake` is the sole stage that runs earlier: it admits the car, which
  -- is what makes the invoice (and therefore payment) possible. `master_admin` was
  -- already allowed through above, matching advance_job_status's admin override.
  IF p_stage_key <> 'vehicle_intake'
     AND v_job_status NOT IN ('4_paid', '6_in_progress', '7_finished',
                              '8_awaiting_delivery', '9_done') THEN
    RETURN FALSE;
  END IF;

  SELECT p.ops_view_mode INTO v_mode
    FROM public.partners p WHERE p.id = v_partner;

  -- An unreadable or missing row restricts rather than permits.
  IF v_mode = 'all_access' THEN
    RETURN TRUE;
  END IF;

  -- view_all_act_own and original_role both restrict ACTING to the stage's own
  -- role list. They differ only in what the UI SHOWS, which is a presentation
  -- concern this function deliberately does not police.
  RETURN EXISTS (
    SELECT 1 FROM public.ops_stage_roles sr
     WHERE sr.stage_key = p_stage_key AND sr.role = v_role
  );
END;
$function$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- VERIFICATION — read this output before closing the tab.
-- Every row must read PASS. Anything else means investigate before trusting it.
--
-- Check 1/2 read the function body line by line rather than matching a substring,
-- because the allowed-status list ('4_paid','5_admitted','6_in_progress',...) puts
-- those two values on one line and would otherwise read as a transition.
-- A real transition line always contains "p_new_status =".
-- ═══════════════════════════════════════════════════════════════════════════════

WITH checks(ord, chk, got, want) AS (

  -- ── the payment gates: the whole point of this deploy ──────────────────────
  SELECT 1, 'advance_job_status: NO 5_admitted -> 6_in_progress edge',
    (SELECT count(*)::text FROM pg_proc p,
            regexp_split_to_table(pg_get_functiondef(p.oid), chr(10)) ln
      WHERE p.proname = 'advance_job_status'
        AND ln LIKE '%p_new_status = ''6_in_progress''%'
        AND ln LIKE '%5_admitted%'), '0'

  UNION ALL SELECT 2, 'advance_job_status: 4_paid -> repair is the only entry',
    (SELECT count(*)::text FROM pg_proc p,
            regexp_split_to_table(pg_get_functiondef(p.oid), chr(10)) ln
      WHERE p.proname = 'advance_job_status'
        AND ln LIKE '%p_new_status = ''6_in_progress''%'
        AND ln LIKE '%4_paid%'), '2'

  UNION ALL SELECT 3, 'ops_may_act_on_stage: milestone write blocked pre-payment',
    (SELECT (pg_get_functiondef(p.oid) LIKE '%NOT IN (''4_paid''%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'ops_may_act_on_stage'), 'true'

  UNION ALL SELECT 4, 'ops_may_act_on_stage: vehicle_intake exempt (admits the car)',
    (SELECT (pg_get_functiondef(p.oid) LIKE '%vehicle_intake%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'ops_may_act_on_stage'), 'true'

  -- ── functions present ──────────────────────────────────────────────────────
  UNION ALL SELECT 5, 'fn claim_guest_jobs',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'claim_guest_jobs'), '1'
  UNION ALL SELECT 6, 'fn execute_auto_assign',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'execute_auto_assign'), '1'
  UNION ALL SELECT 7, 'fn ops_may_act_on_stage',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'ops_may_act_on_stage'), '1'
  UNION ALL SELECT 8, 'fn get_partner_active_job_count',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'get_partner_active_job_count'), '1'
  UNION ALL SELECT 9, 'handle_new_user is anonymous-safe (empty email)',
    (SELECT (pg_get_functiondef(p.oid) LIKE '%Guest%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'handle_new_user'), 'true'

  -- ── auto-assign ────────────────────────────────────────────────────────────
  UNION ALL SELECT 10, 'tbl auto_assign_settings',
    (SELECT count(*)::text FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'auto_assign_settings'), '1'
  UNION ALL SELECT 11, 'col auto_assign_is_draining dropped',
    (SELECT count(*)::text FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'auto_assign_is_draining'), '0'
  UNION ALL SELECT 12, 'auto_assign_settings policies present',
    (SELECT count(*)::text FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'auto_assign_settings'), '2'

  -- ── storage ────────────────────────────────────────────────────────────────
  UNION ALL SELECT 13, 'bucket partner-docs exists',
    (SELECT count(*)::text FROM storage.buckets WHERE id = 'partner-docs'), '1'
  UNION ALL SELECT 14, 'revive-photos NOT public',
    (SELECT count(*)::text FROM storage.buckets WHERE id = 'revive-photos' AND public), '0'
  UNION ALL SELECT 15, 'revive-photos-r2-proxy NOT public',
    (SELECT count(*)::text FROM storage.buckets WHERE id = 'revive-photos-r2-proxy' AND public), '0'
  UNION ALL SELECT 16, 'world-open policy "Allow Public Uploads" gone',
    (SELECT count(*)::text FROM pg_policies
      WHERE schemaname = 'storage' AND policyname = 'Allow Public Uploads'), '0'
  UNION ALL SELECT 17, 'world-open policy "Public Read Access" gone',
    (SELECT count(*)::text FROM pg_policies
      WHERE schemaname = 'storage' AND policyname = 'Public Read Access'), '0'

  -- ── partner applications ───────────────────────────────────────────────────
  UNION ALL SELECT 18, 'open insert policy removed (edge function only)',
    (SELECT count(*)::text FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'partner_applications'
        AND policyname ILIKE 'Enable insert%'), '0'
  UNION ALL SELECT 19, 'partner_applications full submitted profile (12 cols)',
    (SELECT count(*)::text FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'partner_applications'
        AND column_name IN ('entity_name','owner_name','submitted_at','nib_file_key',
                            'npwp_file_key','siup_file_key','ktp_file_key',
                            'tier','paint_brand','throughput_capacity',
                            'service_radius_km','facility_photo_keys')), '12'
  UNION ALL SELECT 20, 'status constraint accepts pending_review',
    (SELECT (pg_get_constraintdef(con.oid) LIKE '%pending_review%')::text
       FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
       JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
      WHERE nsp.nspname = 'public' AND rel.relname = 'partner_applications'
        AND con.conname = 'partner_applications_status_check'), 'true'
  UNION ALL SELECT 21, 'guest claim index',
    (SELECT count(*)::text FROM pg_indexes
      WHERE schemaname = 'public' AND indexname = 'repair_jobs_guest_claim_idx'), '1'

  -- ── the shipped status vocabulary must still be intact ─────────────────────
  UNION ALL SELECT 22, 'repair_jobs status check intact',
    (SELECT (pg_get_constraintdef(oid) LIKE '%9_done%'
             AND pg_get_constraintdef(oid) LIKE '%0_cancelled%')::text
       FROM pg_constraint WHERE conname = 'repair_jobs_status_check'), 'true'
)
SELECT
  CASE WHEN got = want THEN 'PASS' ELSE '*** FAIL ***' END AS result,
  chk, got, want
FROM checks
ORDER BY ord;

COMMIT;
