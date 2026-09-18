-- =============================================================================
-- Migration: Fix profiles RLS — partners can read their own staff members
-- Date: 2026-09-18
-- Problem: The existing profiles SELECT policy only allows:
--   - master_admin (all rows)
--   - auth.uid() = id (own row only)
-- A partner_mechanic querying their staff (same partner_id) gets zero rows
-- because RLS silently filters them out.
-- Fix: Add a policy allowing partner roles to read profiles that share
--      the same partner_id as the caller (from JWT app_metadata).
-- =============================================================================

DROP POLICY IF EXISTS "Partners can read their workshop members" ON public.profiles;

CREATE POLICY "Partners can read their workshop members"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (
    -- Caller must be a partner role
    (auth.jwt() -> 'app_metadata' ->> 'role') IN (
      'partner_mechanic', 'partner_staff', 'partner_driver'
    )
    -- The profile being read must share the caller's partner_id
    AND partner_id IS NOT NULL
    AND partner_id = (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
  );
