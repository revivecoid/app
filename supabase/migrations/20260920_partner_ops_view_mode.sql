-- =============================================================================
-- Workshop ops access mode
-- Date: 2026-09-20
--
-- Staff and drivers were locked to a single job type: staff only self-delivery
-- intake, drivers only valet pickup. A customer changing their mind mid-job made
-- that split brittle. This adds a workshop-wide switch, DEFAULTING TO FULL ACCESS
-- as requested — an owner can tighten their workshop back to the strict per-role
-- split instead of having to opt in to flexibility.
--
--   'all_access' (default) — every staff/driver sees every tab and every job in
--       the workshop and may complete any stage photo.
--   'original_role' — the previous strict behaviour, restored exactly:
--       partner_staff  -> self-deliver intake, no pickup jobs, no 'delivery' stage
--       partner_driver -> pickup/valet only, no floor jobs, no floor stages
--
-- SECURITY POSTURE — read before relying on this column for anything.
-- The database has never enforced the staff/driver split: repair_jobs and
-- job_milestones policies scope by partner_id alone, so RLS already grants both
-- roles read/write on every job in their own workshop. This column therefore
-- drives client-side presentation only. It is a workflow preference, NOT a
-- security boundary, and must not be treated as one.
-- =============================================================================

-- Column exists already in environments where the first cut of this migration
-- ran with the stricter default; IF NOT EXISTS keeps this idempotent.
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS ops_view_mode text NOT NULL DEFAULT 'all_access';

-- Re-assert the default so an environment created with the old 'original_role'
-- default converges on the intended one.
ALTER TABLE public.partners
  ALTER COLUMN ops_view_mode SET DEFAULT 'all_access';

-- One-time backfill for rows that predate the default change. Existing workshops
-- gain full access, matching the requested default; an owner who wants the strict
-- split switches it back from Partner Settings.
UPDATE public.partners
   SET ops_view_mode = 'all_access'
 WHERE ops_view_mode = 'original_role';

-- Constrain to the two known modes so a typo fails loudly at write time rather
-- than silently reading as "not all_access".
ALTER TABLE public.partners
  DROP CONSTRAINT IF EXISTS partners_ops_view_mode_check;

ALTER TABLE public.partners
  ADD CONSTRAINT partners_ops_view_mode_check
  CHECK (ops_view_mode IN ('all_access', 'original_role'));

COMMENT ON COLUMN public.partners.ops_view_mode IS
  'Workshop-wide ops view mode for staff and drivers: '
  'all_access = all tabs, all jobs, all stages (default), '
  'original_role = strict per-role split. '
  'Client-side workflow preference only — NOT a security boundary; RLS on '
  'repair_jobs/job_milestones already grants both roles the whole workshop.';


-- ---------------------------------------------------------------------------
-- Lock the partner row down to the owner.
--
-- The existing UPDATE policy ("Master Admins can update all partners") allowed
-- is_master_admin() OR get_my_partner_id() = id. Because staff and drivers carry
-- partner_id in their token, get_my_partner_id() matched for THEM TOO — so any
-- staff member or driver could rewrite EVERY column of their workshop row:
-- status, tier, is_active, suspended_at, and the document keys. Verified by
-- simulation: a partner_staff UPDATE succeeded before this change. That is a
-- pre-existing hole, unrelated to ops_view_mode, and it also made the requested
-- "owner-only control" impossible.
--
-- The owner is admitted two ways on purpose:
--   * has_partner_membership(...) — the memberships source of truth, and
--   * jwt role = 'partner_mechanic' — a fallback so a legitimately-registered
--     owner can never be locked out if their membership row is missing or late
--     (handle_new_user() only provisions a customer membership, so a newly
--     approved workshop owner may not have an owner/mechanic row yet).
-- Staff and drivers satisfy neither: their jwt role is partner_staff /
-- partner_driver and they hold no owner/mechanic membership.
--
-- Reads are untouched — workshop members must still read this row, since the
-- client resolves ops_view_mode from it.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Master Admins can update all partners" ON public.partners;
-- also drop the new one so this migration can be re-run without error
DROP POLICY IF EXISTS "Owner and admins can update their partner row" ON public.partners;

CREATE POLICY "Owner and admins can update their partner row"
  ON public.partners
  FOR UPDATE
  TO authenticated
  USING (
    is_master_admin()
    OR has_partner_membership(id, ARRAY['owner', 'mechanic']::public.membership_role[])
    OR (
      get_my_partner_id() = id
      AND COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'partner_mechanic'
    )
  )
  WITH CHECK (
    is_master_admin()
    OR has_partner_membership(id, ARRAY['owner', 'mechanic']::public.membership_role[])
    OR (
      get_my_partner_id() = id
      AND COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'partner_mechanic'
    )
  );
