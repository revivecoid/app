-- =============================================================================
-- STEP 2 of 4 — authorization consolidation onto memberships
-- Date: 2026-09-20
--
-- REQUIRES 20260920_memberships_foundation.sql to be applied FIRST (this
-- migration moves is_master_admin() onto memberships; if the table were empty
-- the admin would lose access).
--
-- What this fixes
-- ---------------
-- 1. CRITICAL — every user is an admin.
--    profiles.admin_level defaults to 'admin', handle_new_user() never sets it,
--    and is_admin() tests admin_level IN ('admin','sysadmin'). Verified: 11 of
--    11 users evaluate TRUE. Five policies are gated on is_admin() alone
--    (partners SELECT/UPDATE, repair_jobs SELECT/UPDATE, profiles SELECT), so
--    any signed-in customer could read and update every job and workshop.
--    The blast radius: partners(2 rows), profiles(11 rows), repair_jobs(5).
--
-- 2. An unguarded role writer reachable by anon.
--    set_user_role(uuid, text) had EXECUTE granted to anon AND authenticated,
--    performed NO admin check, and wrote raw_user_meta_data.role for any user.
--    Dropped.
--
-- 3. Admin state lived in three places at once (profiles.role,
--    profiles.admin_level, app_metadata.role) with no single source of truth.
--
-- Design
-- ------
-- memberships is the single source of truth. Two distinct tiers, so a second
-- admin level can be added later WITHOUT touching any policy:
--
--   is_master_admin()  -> holds platform/master_admin
--   is_admin()         -> holds ANY active platform-scope membership
--
-- Today only master_admin holds a platform row, so the two are equivalent, and
-- exactly one user (008f9382) keeps access — the 10 non-admins lose it. When a
-- finer tier is wanted later, ALTER TYPE membership_role ADD VALUE 'admin' and
-- insert a platform row; is_admin() picks it up with no policy changes.
--
-- profiles.role and profiles.admin_level are still WRITTEN (for transition and
-- because the Flutter client reads app_metadata), but they are no longer read
-- for any authorization decision. Dropping them is step 4.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Drop the unguarded role writer (anon-executable, no admin check)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.set_user_role(uuid, text);


-- ---------------------------------------------------------------------------
-- 2. is_master_admin() -> memberships platform/master_admin
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_master_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
     WHERE user_id = auth.uid()
       AND scope   = 'platform'
       AND role    = 'master_admin'
       AND status  = 'active'
  );
$$;

-- Policies are declared FOR {public}/authenticated and evaluate these helpers
-- as the querying role, so anon must retain EXECUTE or anon queries raise
-- "permission denied for function" while merely testing a policy.
GRANT EXECUTE ON FUNCTION public.is_master_admin() TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. is_admin() -> ANY active platform membership
--    Replaces the admin_level check that returned TRUE for everyone.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
     WHERE user_id = auth.uid()
       AND scope   = 'platform'
       AND status  = 'active'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 4. get_admin_profile() -> admin_level DERIVED, never read from the column.
--    Keeps the 'admin_level' key because admin_dashboard_controller.dart reads
--    data['admin_level']; it now reports the truth instead of a column default.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_admin_profile()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_build_object(
    'full_name',   p.full_name,
    'role',        p.role,
    'admin_level', (
        SELECT CASE
                 WHEN bool_or(m.role = 'master_admin') THEN 'sysadmin'
                 ELSE 'admin'
               END
          FROM public.memberships m
         WHERE m.user_id = auth.uid()
           AND m.scope   = 'platform'
           AND m.status  = 'active'
      ),
    'email',       u.email
  )
  INTO result
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE p.id = auth.uid()
  LIMIT 1;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_admin_profile() FROM anon;


-- ---------------------------------------------------------------------------
-- 5. handle_new_user() -> provision the customer membership too.
--    Replacements for this trigger must be found with a diagnostic; see the
--    project skill. This body mirrors the original plus the membership insert.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.email,
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;

  -- memberships is the source of truth; keep it populated for every new signup
  INSERT INTO public.memberships (user_id, scope, role, status)
  VALUES (NEW.id, 'customer', 'customer', 'active')
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;


-- ---------------------------------------------------------------------------
-- 6. set_user_role(uuid, text, uuid) -> write memberships as the truth.
--    Existing semantics preserved (jsonb result shape, self-demotion guard,
--    partner_id required for staff/driver, audit log). profiles and
--    app_metadata are still written for the transition, but memberships leads.
--
--    Membership rule: everyone may hold a customer membership (a mechanic can
--    be a customer of another workshop — confirmed business rule), so the
--    customer row is never revoked. Partner rows are exclusive per org, so any
--    partner membership not matching the new (org, role) is removed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_user_role(
  target_user_id uuid,
  new_role text,
  new_partner_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_role    TEXT;
  v_user_email  TEXT;
  v_full_name   TEXT;
  v_scope       public.membership_scope;
  v_mrole       public.membership_role;
BEGIN
  IF NOT public.is_master_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden: admin role required');
  END IF;

  IF new_role NOT IN ('customer', 'partner_mechanic', 'master_admin', 'partner_staff', 'partner_driver') THEN
    RETURN jsonb_build_object('success', false, 'error',
        format('Invalid role "%s".', new_role));
  END IF;

  IF target_user_id = auth.uid() AND new_role <> 'master_admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot demote your own admin account.');
  END IF;

  SELECT p.role, p.full_name, u.email
  INTO v_old_role, v_full_name, v_user_email
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE u.id = target_user_id;

  IF v_user_email IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found.');
  END IF;

  IF new_role IN ('partner_staff', 'partner_driver') AND new_partner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error',
        'partner_id is required when assigning staff/driver role.');
  END IF;

  IF new_role IN ('customer', 'master_admin') THEN
    new_partner_id := NULL;
  END IF;

  -- ── profiles (transition; no longer read for authorization) ─────────────
  INSERT INTO public.profiles (id, full_name, email, role, partner_id)
  VALUES (target_user_id, COALESCE(v_full_name, split_part(v_user_email, '@', 1)),
          v_user_email, new_role, new_partner_id)
  ON CONFLICT (id) DO UPDATE
  SET role = new_role,
      partner_id = new_partner_id;

  -- ── app_metadata (still read by the Flutter client for UI gating) ───────
  IF new_partner_id IS NOT NULL THEN
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
          jsonb_set(COALESCE(raw_app_meta_data, '{}'::jsonb), '{role}',
                    to_jsonb(new_role)),
          '{partner_id}', to_jsonb(new_partner_id::text))
    WHERE id = target_user_id;
  ELSE
    UPDATE auth.users
    SET raw_app_meta_data = (COALESCE(raw_app_meta_data, '{}'::jsonb) - 'partner_id')
                            || jsonb_build_object('role', new_role)
    WHERE id = target_user_id;
  END IF;

  -- ── memberships: THE source of truth ───────────────────────────────────
  v_scope := CASE new_role
               WHEN 'master_admin' THEN 'platform'
               WHEN 'customer'     THEN 'customer'
               ELSE 'partner'
             END::public.membership_scope;

  v_mrole := CASE new_role
               WHEN 'master_admin'     THEN 'master_admin'
               WHEN 'customer'         THEN 'customer'
               WHEN 'partner_mechanic' THEN 'mechanic'
               WHEN 'partner_staff'    THEN 'staff'
               WHEN 'partner_driver'   THEN 'driver'
             END::public.membership_role;

  -- granting a platform role replaces any other platform role
  IF v_scope = 'platform' THEN
    DELETE FROM public.memberships
     WHERE user_id = target_user_id AND scope = 'platform';
  END IF;

  -- partner memberships are exclusive per org: drop the ones that no longer apply
  IF v_scope = 'partner' THEN
    DELETE FROM public.memberships
     WHERE user_id = target_user_id
       AND scope   = 'partner'
       AND NOT (org_id = new_partner_id AND role = v_mrole);
  ELSIF new_role = 'customer' THEN
    -- moving to plain customer revokes partner standing, but NOT the customer row
    DELETE FROM public.memberships
     WHERE user_id = target_user_id AND scope = 'partner';
  END IF;

  INSERT INTO public.memberships (user_id, scope, role, org_id, status)
  VALUES (target_user_id, v_scope, v_mrole,
          CASE WHEN v_scope = 'partner' THEN new_partner_id END, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES (
    'SET_USER_ROLE', 'profiles', target_user_id, auth.uid(),
    jsonb_build_object('old_role', v_old_role, 'new_role', new_role,
                       'partner_id', new_partner_id)
  );

  RETURN jsonb_build_object(
    'success', true, 'user_id', target_user_id,
    'old_role', v_old_role, 'new_role', new_role, 'email', v_user_email
  );
END;
$$;

-- only signed-in callers may even reach the admin check; the function itself
-- still enforces is_master_admin(). anon has no business here.
REVOKE EXECUTE ON FUNCTION public.set_user_role(uuid, text, uuid) FROM anon;


-- ---------------------------------------------------------------------------
-- 7. list_all_users() — revoke anon (admin RPC, not referenced by any policy)
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.list_all_users() FROM anon;


-- ---------------------------------------------------------------------------
-- 8. Verify the two tiers for existing users.
--    NOTE: is_admin()/is_master_admin() cannot be exercised in a migration body
--    — auth.uid() is NULL there, so they correctly return false. Read the
--    membership rows instead; the helpers are asserted separately with a
--    simulated JWT.
-- ---------------------------------------------------------------------------
SELECT p.role::text                                  AS profile_role,
       COALESCE(u.raw_app_meta_data ->> 'role', '-') AS jwt_role,
       COALESCE((
         SELECT string_agg(m.scope::text || ':' || m.role::text, ', ')
           FROM public.memberships m
          WHERE m.user_id = p.id AND m.status = 'active'
       ), '(none)')                                  AS memberships,
       EXISTS (SELECT 1 FROM public.memberships m
                WHERE m.user_id = p.id AND m.scope = 'platform'
                  AND m.status = 'active')           AS would_be_admin
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
 ORDER BY would_be_admin DESC, p.role;
