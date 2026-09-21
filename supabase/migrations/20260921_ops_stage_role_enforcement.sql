-- =============================================================================
-- Ops stage-role enforcement, and a third access mode (view_all_act_own)
-- Date: 2026-09-21
--
-- Why
-- ---
-- A driver completed the Disassembly stage, which their own stage role list
-- excludes. The list lived ONLY in Dart (`kOpsStages[].allowedRoles`), so the
-- database had no idea a role split existed: RLS on job_milestones scopes by
-- TENANT (`rj.partner_id = <my partner_id>`), which grants every workshop member
-- every stage. Hiding a tile in Flutter was never enforcement.
--
-- This migration moves the mapping into the database, adds a helper that answers
-- "may THIS caller act on THIS stage of THIS job", and puts that helper into
-- RESTRICTIVE policies so the tenant scoping stays and the role gate is added on
-- top. Restrictive policies AND with the permissive ones already present, so
-- nothing that works today for a legitimate operator changes.
--
-- The seed below was GENERATED from the Dart stage list, so the two definitions
-- start out provably identical rather than matching by hand.
--
-- New mode
-- --------
--   all_access      (default) view all, act on all      [unchanged]
--   view_all_act_own          view all, act only on own [NEW]
--   original_role             the strict per-role split [unchanged]
--
-- view_all_act_own is the one the user asked for: a driver sees every job and
-- stage but cannot interfere with another role's production stage.
--
-- Residual (deliberate, stated not hidden)
-- ----------------------------------------
-- advance_job_status is NOT gated here. It is shared with the customer flows
-- (booking, payment), so gating it by ops role would break those. A workshop
-- member who is refused a stage write cannot advance the job through this path
-- because the client only calls it after a successful write — but a hand-crafted
-- call could. Closing that needs a separate ownership-aware gate.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS, ON CONFLICT DO UPDATE seed,
-- CREATE OR REPLACE functions, DROP POLICY IF EXISTS before each CREATE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. The stage -> role mapping, as data
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ops_stage_roles (
  stage_key TEXT NOT NULL,
  role      TEXT NOT NULL,
  PRIMARY KEY (stage_key, role)
);

COMMENT ON TABLE public.ops_stage_roles IS
  'Which role may complete which ops stage. Enforced by ops_may_act_on_stage() in '
  'restrictive policies on job_milestones / job_milestone_photos. Mirrors '
  'kOpsStages[].allowedRoles in ops_stage_photo_screen.dart.';

ALTER TABLE public.ops_stage_roles ENABLE ROW LEVEL SECURITY;

-- Readable by any signed-in user: the ops UI reads this to render tiles, and it
-- holds no sensitive data (it is a role-per-stage whitelist).
DROP POLICY IF EXISTS "ops_stage_roles readable" ON public.ops_stage_roles;
CREATE POLICY "ops_stage_roles readable"
  ON public.ops_stage_roles FOR SELECT TO authenticated
  USING (true);

-- Writable only by a platform admin: this is the enforcement table, so a
-- workshop must not be able to widen its own permissions by editing it.
DROP POLICY IF EXISTS "ops_stage_roles admin write" ON public.ops_stage_roles;
CREATE POLICY "ops_stage_roles admin write"
  ON public.ops_stage_roles FOR ALL TO authenticated
  USING (is_master_admin())
  WITH CHECK (is_master_admin());

-- Seed / keep in sync. DO UPDATE rather than DO NOTHING so a role added in Dart
-- and regenerated here actually lands on re-apply.
INSERT INTO public.ops_stage_roles (stage_key, role) VALUES
  ('vehicle_intake', 'partner_staff'),
  ('vehicle_intake', 'partner_driver'),
  ('vehicle_intake', 'partner_mechanic'),
  ('vehicle_intake', 'master_admin'),
  ('disassembly', 'partner_staff'),
  ('disassembly', 'partner_mechanic'),
  ('disassembly', 'master_admin'),
  ('welding', 'partner_staff'),
  ('welding', 'partner_mechanic'),
  ('welding', 'master_admin'),
  ('body_filler', 'partner_staff'),
  ('body_filler', 'partner_mechanic'),
  ('body_filler', 'master_admin'),
  ('painting', 'partner_staff'),
  ('painting', 'partner_mechanic'),
  ('painting', 'master_admin'),
  ('polishing', 'partner_staff'),
  ('polishing', 'partner_mechanic'),
  ('polishing', 'master_admin'),
  ('qc_finished', 'partner_staff'),
  ('qc_finished', 'partner_mechanic'),
  ('qc_finished', 'master_admin'),
  ('delivery', 'partner_staff'),
  ('delivery', 'partner_driver'),
  ('delivery', 'partner_mechanic'),
  ('delivery', 'master_admin')
ON CONFLICT (stage_key, role) DO UPDATE SET role = EXCLUDED.role;

-- Remove rows for stages/roles no longer in the Dart list, so a role that was
-- deliberately removed cannot linger and keep granting access.
DELETE FROM public.ops_stage_roles
 WHERE (stage_key, role) NOT IN (VALUES
     ('vehicle_intake', 'partner_staff'),
     ('vehicle_intake', 'partner_driver'),
     ('vehicle_intake', 'partner_mechanic'),
     ('vehicle_intake', 'master_admin'),
     ('disassembly', 'partner_staff'),
     ('disassembly', 'partner_mechanic'),
     ('disassembly', 'master_admin'),
     ('welding', 'partner_staff'),
     ('welding', 'partner_mechanic'),
     ('welding', 'master_admin'),
     ('body_filler', 'partner_staff'),
     ('body_filler', 'partner_mechanic'),
     ('body_filler', 'master_admin'),
     ('painting', 'partner_staff'),
     ('painting', 'partner_mechanic'),
     ('painting', 'master_admin'),
     ('polishing', 'partner_staff'),
     ('polishing', 'partner_mechanic'),
     ('polishing', 'master_admin'),
     ('qc_finished', 'partner_staff'),
     ('qc_finished', 'partner_mechanic'),
     ('qc_finished', 'master_admin'),
     ('delivery', 'partner_staff'),
     ('delivery', 'partner_driver'),
     ('delivery', 'partner_mechanic'),
     ('delivery', 'master_admin')
 );


-- ---------------------------------------------------------------------------
-- 2. The gate
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER so policy evaluation does not depend on the caller having
-- SELECT on partners/repair_jobs (they do, but relying on it makes the gate
-- fragile and slow), and so a policy can never recurse into the table it
-- protects.
CREATE OR REPLACE FUNCTION public.ops_may_act_on_stage(
  p_job_id    UUID,
  p_stage_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role      TEXT;
  v_partner   UUID;
  v_mode      TEXT;
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
  IF v_partner IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.repair_jobs r
     WHERE r.id = p_job_id AND r.partner_id = v_partner
  ) THEN
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
$$;

REVOKE EXECUTE ON FUNCTION public.ops_may_act_on_stage(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_may_act_on_stage(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. Enforce it on the client-side write paths
-- ---------------------------------------------------------------------------
-- Intake and delivery go through SECURITY DEFINER RPCs, which bypass RLS, so
-- they are gated in their own bodies in a separate migration. These policies
-- cover the MID-REPAIR stages, which the Flutter client writes directly over
-- PostgREST.
--
-- RESTRICTIVE (AS RESTRICTIVE) so they AND with the existing tenant policies
-- rather than adding an alternative path. A non-restrictive policy here would be
-- useless: permissive policies are OR-ed, so the existing tenant policy would
-- keep granting access.

DROP POLICY IF EXISTS "ops stage role gate: milestones insert" ON public.job_milestones;
CREATE POLICY "ops stage role gate: milestones insert"
  ON public.job_milestones AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (public.ops_may_act_on_stage(job_id, stage_key));

DROP POLICY IF EXISTS "ops stage role gate: milestones update" ON public.job_milestones;
CREATE POLICY "ops stage role gate: milestones update"
  ON public.job_milestones AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (public.ops_may_act_on_stage(job_id, stage_key))
  WITH CHECK (public.ops_may_act_on_stage(job_id, stage_key));

-- Photos hang off a milestone, so resolve the stage through it. The existing
-- INSERT policy already proves the milestone belongs to this workshop's job; this
-- adds the role question.
DROP POLICY IF EXISTS "ops stage role gate: photos insert" ON public.job_milestone_photos;
CREATE POLICY "ops stage role gate: photos insert"
  ON public.job_milestone_photos AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.job_milestones m
     WHERE m.id = milestone_id
       AND public.ops_may_act_on_stage(m.job_id, m.stage_key)
  ));


-- ---------------------------------------------------------------------------
-- 4. The third mode
-- ---------------------------------------------------------------------------
-- The existing CHECK allows only all_access / original_role, so writing the new
-- value would fail with 23514 without this.
ALTER TABLE public.partners DROP CONSTRAINT IF EXISTS partners_ops_view_mode_check;
ALTER TABLE public.partners ADD CONSTRAINT partners_ops_view_mode_check
  CHECK (ops_view_mode = ANY (ARRAY['all_access'::text, 'view_all_act_own'::text, 'original_role'::text]));


-- ---------------------------------------------------------------------------
-- 5. Verify
-- ---------------------------------------------------------------------------
-- Reported as the LAST result set: the Management API returns only that one.
SELECT
  (SELECT count(*) FROM public.ops_stage_roles)                        AS seeded_rows,
  (SELECT count(DISTINCT stage_key) FROM public.ops_stage_roles)       AS stages_covered,
  (SELECT string_agg(DISTINCT role, ',' ORDER BY role)
     FROM public.ops_stage_roles)                                      AS roles_present,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname='public' AND policyname LIKE 'ops stage role gate%') AS gate_policies,
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conname = 'partners_ops_view_mode_check')                    AS mode_check;
