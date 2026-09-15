-- =============================================================================
-- Phase 9: Internal Audit Remediation (INT-01 through INT-12)
-- Date: 2026-09-15
-- =============================================================================

-- ---------------------------------------------------------------------------
-- INT-04: toggle_partner_online RPC
-- Allows a partner to toggle their own availability status.
-- CRITICAL: Blocks suspended partners (admin-set is_active=false AND
--           suspended_at IS NOT NULL) from reactivating themselves.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION toggle_partner_online(
  p_partner_id UUID,
  p_is_active   BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_partner_id UUID;
  v_is_suspended      BOOLEAN;
BEGIN
  -- 1. Verify caller owns this partner record
  SELECT (raw_app_meta_data->>'partner_id')::uuid
    INTO v_caller_partner_id
    FROM auth.users
   WHERE id = auth.uid();

  IF v_caller_partner_id IS DISTINCT FROM p_partner_id THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You can only toggle your own availability.';
  END IF;

  -- 2. Check if partner has been suspended by admin (suspended_at is set)
  SELECT (suspended_at IS NOT NULL)
    INTO v_is_suspended
    FROM partners
   WHERE id = p_partner_id;

  IF v_is_suspended AND p_is_active = TRUE THEN
    RAISE EXCEPTION 'FORBIDDEN: Your account has been suspended by an administrator. Contact support to appeal.';
  END IF;

  -- 3. Safe to toggle
  UPDATE partners
     SET is_active   = p_is_active,
         updated_at  = now()
   WHERE id = p_partner_id;
END;
$$;

REVOKE ALL ON FUNCTION toggle_partner_online(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION toggle_partner_online(UUID, BOOLEAN) TO authenticated;


-- ---------------------------------------------------------------------------
-- INT-07: admin_soft_delete_partner RPC
-- Soft-deletes a partner (sets deleted_at, deactivates) and logs the action.
-- Hard DELETE is blocked by the RLS policy below.
-- ---------------------------------------------------------------------------

-- Add deleted_at column if not already present
ALTER TABLE partners ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ;
ALTER TABLE partners ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;
ALTER TABLE partners ADD COLUMN IF NOT EXISTS deleted_by  UUID REFERENCES auth.users(id);

-- Create audit log table if not exists
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action      TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id   UUID NOT NULL,
  performed_by UUID NOT NULL REFERENCES auth.users(id),
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only master admins can read the audit log
ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_audit_log_select ON admin_audit_log;
CREATE POLICY admin_audit_log_select ON admin_audit_log
  FOR SELECT TO authenticated
  USING (is_master_admin());


CREATE OR REPLACE FUNCTION admin_soft_delete_partner(p_partner_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Must be master admin
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can delete partners.';
  END IF;

  -- 2. Soft-delete: set deleted_at, deactivate
  UPDATE partners
     SET deleted_at  = now(),
         deleted_by  = auth.uid(),
         is_active   = FALSE,
         updated_at  = now()
   WHERE id = p_partner_id
     AND deleted_at IS NULL; -- Idempotent

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Partner does not exist or already deleted.';
  END IF;

  -- 3. Write audit trail
  INSERT INTO admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES (
    'SOFT_DELETE_PARTNER',
    'partners',
    p_partner_id,
    auth.uid(),
    jsonb_build_object('deleted_at', now())
  );
END;
$$;

REVOKE ALL ON FUNCTION admin_soft_delete_partner(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_soft_delete_partner(UUID) TO authenticated;


-- Block direct DELETE on partners for non-service-role callers
-- (Admin must use admin_soft_delete_partner RPC instead)
DROP POLICY IF EXISTS partners_delete ON partners;
CREATE POLICY partners_delete ON partners
  FOR DELETE TO authenticated
  USING (FALSE); -- Never allow direct DELETE; use soft-delete RPC


-- ---------------------------------------------------------------------------
-- INT-04: admin_suspend_partner RPC  
-- Separate function for admin suspension (sets suspended_at).
-- This is what admins use — partners cannot call this.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION admin_suspend_partner(p_partner_id UUID, p_suspend BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can suspend partners.';
  END IF;

  UPDATE partners
     SET suspended_at = CASE WHEN p_suspend THEN now() ELSE NULL END,
         is_active    = NOT p_suspend,
         updated_at   = now()
   WHERE id = p_partner_id;

  INSERT INTO admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES (
    CASE WHEN p_suspend THEN 'SUSPEND_PARTNER' ELSE 'UNSUSPEND_PARTNER' END,
    'partners',
    p_partner_id,
    auth.uid(),
    jsonb_build_object('suspended', p_suspend, 'at', now())
  );
END;
$$;

REVOKE ALL ON FUNCTION admin_suspend_partner(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_suspend_partner(UUID, BOOLEAN) TO authenticated;


-- ---------------------------------------------------------------------------
-- INT-04: Update admin_partner_profile_controller suspend/unsuspend
-- Update existing suspendPartner/restorePartner calls to use new RPC
-- (No SQL needed — handled in Dart)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Exclude soft-deleted partners from regular queries
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS partners_select ON partners;
CREATE POLICY partners_select ON partners
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    OR is_master_admin()  -- admins can still see deleted records
  );


-- ---------------------------------------------------------------------------
-- INT-08: job_milestones RLS — only ops staff of the assigned partner
-- can insert milestones for a job.
-- ---------------------------------------------------------------------------

ALTER TABLE job_milestones ENABLE ROW LEVEL SECURITY;

-- Read: Ops staff for the assigned partner, the customer who owns the job, and admins
DROP POLICY IF EXISTS job_milestones_select ON job_milestones;
CREATE POLICY job_milestones_select ON job_milestones
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR EXISTS (
      SELECT 1 FROM repair_jobs rj
       WHERE rj.id = job_milestones.job_id
         AND (
           rj.customer_id = auth.uid()                                          -- customer
           OR (auth.jwt()->'app_metadata'->>'partner_id')::uuid = rj.partner_id -- ops staff
         )
    )
  );

-- Insert: Only ops staff of the partner assigned to this job
DROP POLICY IF EXISTS job_milestones_insert ON job_milestones;
CREATE POLICY job_milestones_insert ON job_milestones
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM repair_jobs rj
       WHERE rj.id = job_milestones.job_id
         AND (auth.jwt()->'app_metadata'->>'partner_id')::uuid = rj.partner_id
         AND rj.status NOT IN ('1_pending', '2_estimated', '9_completed', '0_cancelled')
    )
  );

-- Ops staff cannot update or delete milestones (immutable audit trail)
DROP POLICY IF EXISTS job_milestones_update ON job_milestones;
CREATE POLICY job_milestones_update ON job_milestones
  FOR UPDATE TO authenticated
  USING (is_master_admin());

DROP POLICY IF EXISTS job_milestones_delete ON job_milestones;
CREATE POLICY job_milestones_delete ON job_milestones
  FOR DELETE TO authenticated
  USING (is_master_admin());


-- ---------------------------------------------------------------------------
-- INT-09: CSRF on OAuth — N/A
-- supabase_flutter uses PKCE flow by default which includes a server-generated
-- state parameter. No client-side changes needed.
-- ---------------------------------------------------------------------------
