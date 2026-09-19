-- =============================================================================
-- STEP 1 of 4 — memberships foundation (table + enums + helpers + backfill)
-- Date: 2026-09-20
--
-- NOT YET APPLIED. Review + dry-run first (see the accompanying query script).
--
-- Why this exists
-- ---------------
-- The schema says a person has ONE role. The business says a person holds
-- SEVERAL: a partner mechanic can also be a customer of another workshop. So the
-- role is stored in two places that can disagree —
--
--   profiles.role              ('customer' for that user)
--   app_metadata.role          ('partner_mechanic' for the same user)
--
-- — and every guard then guesses which hat is on from the action attempted. Both
-- booking bugs of 2026-09-19 came from that guess:
--   * plain customers: app_metadata.role NULL -> 'not allowed for role <NULL>'
--   * dual-role user : resolved as partner_mechanic -> 'not assigned to your
--                      workshop' when booking their OWN car
--
-- Role is a property of (person, context), not of the person. This models it.
--
-- Scope of THIS step: the table, its enums/indexes/RLS, the helper functions,
-- and the backfill. It changes NO existing policy and NO existing function
-- behaviour, so it is safe to apply on its own. Steps 2-4 (token hook, RLS
-- rewrite, dropping the old columns) follow only after this is verified.
--
-- Notes for the reviewer
-- ----------------------
-- * profiles.admin_level defaults to 'admin' and handle_new_user() never sets
--   it, so is_admin() currently returns TRUE for ALL 11 users, and five
--   policies are gated on is_admin() alone (partners SELECT/UPDATE,
--   repair_jobs SELECT/UPDATE, profiles SELECT). This table is what removes
--   admin_level from the authorization path in step 3. It is NOT fixed here.
-- * Existing helper is_master_admin() reads profiles.role and keeps working
--   untouched. The new helpers are additive under distinct names.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Enums (idempotent)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.membership_scope AS ENUM ('platform', 'customer', 'partner');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.membership_role AS ENUM
    ('master_admin',                        -- platform
     'customer',                            -- customer
     'owner', 'mechanic', 'staff', 'driver');  -- partner
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ---------------------------------------------------------------------------
-- 2. The table
--    One row per (person, context). A dual-role user simply has two rows.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.memberships (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id)   ON DELETE CASCADE,
  scope       public.membership_scope NOT NULL,
  org_id      uuid          REFERENCES public.partners(id) ON DELETE CASCADE,
  role        public.membership_role  NOT NULL,
  status      text NOT NULL DEFAULT 'active',
  created_at  timestamptz DEFAULT now(),

  -- org_id is meaningful only for partner scope; platform/customer are global
  CONSTRAINT memberships_org_scope_check CHECK (
    (scope =  'partner' AND org_id IS NOT NULL) OR
    (scope <> 'partner' AND org_id IS NULL)
  ),
  CONSTRAINT memberships_status_check CHECK (
    status IN ('active', 'invited', 'suspended')
  )
);

-- NULL org_id defeats UNIQUE (NULLs are distinct), so index the COALESCE
CREATE UNIQUE INDEX IF NOT EXISTS memberships_unique
  ON public.memberships (user_id, scope, role,
                         COALESCE(org_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- supports has_partner_role() lookups and per-org staff listing
CREATE INDEX IF NOT EXISTS memberships_org_role_idx
  ON public.memberships (org_id, role) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS memberships_user_idx
  ON public.memberships (user_id) WHERE status = 'active';

COMMENT ON TABLE public.memberships IS
  'What a person IS, per context. Replaces profiles.role + app_metadata.role, '
  'which could disagree and forced every guard to guess.';


-- ---------------------------------------------------------------------------
-- 3. Helpers — declared BEFORE the policies that reference them (CREATE POLICY
--    resolves function OIDs immediately, so a forward reference fails with
--    "function public.has_platform_membership(unknown) does not exist").
--    Additive: the existing is_master_admin() is untouched.
--    SECURITY DEFINER + pinned search_path per project convention.
-- ---------------------------------------------------------------------------

-- platform-scope check (admin / sysadmin live here, not in profiles.admin_level)
CREATE OR REPLACE FUNCTION public.has_platform_membership(p_role public.membership_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
     WHERE user_id = auth.uid()
       AND scope   = 'platform'
       AND role    = p_role
       AND status  = 'active'
  );
$$;

-- partner-scope check against ONE org: "is this user a <role> at this workshop?"
CREATE OR REPLACE FUNCTION public.has_partner_membership(
  p_org_id uuid,
  p_roles  public.membership_role[]
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
     WHERE user_id = auth.uid()
       AND scope   = 'partner'
       AND org_id  = p_org_id
       AND role    = ANY(p_roles)
       AND status  = 'active'
  );
$$;

-- any partner membership at all — for "which hat is this user wearing" screens
CREATE OR REPLACE FUNCTION public.partner_memberships()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'org_id', m.org_id, 'role', m.role, 'status', m.status)), '[]'::jsonb)
    FROM public.memberships m
   WHERE m.user_id = auth.uid() AND m.scope = 'partner';
$$;

GRANT EXECUTE ON FUNCTION public.has_platform_membership(public.membership_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_partner_membership(uuid, public.membership_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_memberships() TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. RLS — a user sees their own memberships; platform admins see all.
--    The helpers above are SECURITY DEFINER, so no policy recursion.
-- ---------------------------------------------------------------------------
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own memberships" ON public.memberships;
CREATE POLICY "Users read own memberships"
  ON public.memberships FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Platform admins manage memberships" ON public.memberships;
CREATE POLICY "Platform admins manage memberships"
  ON public.memberships FOR ALL TO authenticated
  USING (public.has_platform_membership('master_admin'::public.membership_role))
  WITH CHECK (public.has_platform_membership('master_admin'::public.membership_role));

DROP POLICY IF EXISTS "Workshop owners manage their staff" ON public.memberships;
CREATE POLICY "Workshop owners manage their staff"
  ON public.memberships FOR INSERT TO authenticated
  WITH CHECK (
    scope = 'partner'
    AND public.has_partner_membership(org_id, ARRAY['owner']::public.membership_role[])
  );


-- ---------------------------------------------------------------------------
-- 5. Backfill — union BOTH historical sources so nothing is lost.
--    max() ignores NULLs, so a user whose profiles row lacks partner_id but
--    whose app_metadata has it still ends up with the org.
-- ---------------------------------------------------------------------------
WITH raw AS (
  -- source A: profiles
  SELECT p.id AS user_id,
         CASE p.role
           WHEN 'master_admin' THEN 'platform'
           WHEN 'customer'     THEN 'customer'
           ELSE 'partner'
         END::public.membership_scope AS scope,
         CASE p.role
           WHEN 'master_admin'     THEN 'master_admin'
           WHEN 'customer'         THEN 'customer'
           WHEN 'partner_mechanic' THEN 'mechanic'
           WHEN 'partner_staff'    THEN 'staff'
           WHEN 'partner_driver'   THEN 'driver'
         END::public.membership_role AS role,
         CASE WHEN p.role IN ('partner_mechanic','partner_staff','partner_driver')
              THEN p.partner_id END AS org_id
    FROM public.profiles p
   WHERE p.role IN ('master_admin','customer',
                    'partner_mechanic','partner_staff','partner_driver')

  UNION ALL

  -- source B: JWT app_metadata (the second, disagreeing copy)
  SELECT u.id,
         CASE u.raw_app_meta_data ->> 'role'
           WHEN 'master_admin' THEN 'platform'
           WHEN 'customer'     THEN 'customer'
           ELSE 'partner'
         END::public.membership_scope,
         CASE u.raw_app_meta_data ->> 'role'
           WHEN 'master_admin'     THEN 'master_admin'
           WHEN 'customer'         THEN 'customer'
           WHEN 'partner_mechanic' THEN 'mechanic'
           WHEN 'partner_staff'    THEN 'staff'
           WHEN 'partner_driver'   THEN 'driver'
         END::public.membership_role,
         CASE WHEN u.raw_app_meta_data ->> 'role'
                   IN ('partner_mechanic','partner_staff','partner_driver')
              THEN (u.raw_app_meta_data ->> 'partner_id')::uuid END
    FROM auth.users u
   WHERE u.raw_app_meta_data ->> 'role' IN
         ('master_admin','customer','partner_mechanic','partner_staff','partner_driver')
),
per_identity AS (
  SELECT user_id, scope, role,
         (array_agg(org_id) FILTER (WHERE org_id IS NOT NULL))[1] AS org_id
    FROM raw
   WHERE role IS NOT NULL
   GROUP BY user_id, scope, role
)
INSERT INTO public.memberships (user_id, scope, role, org_id, status)
SELECT user_id, scope, role, org_id, 'active'
  FROM per_identity
 WHERE scope <> 'partner' OR org_id IS NOT NULL   -- honour the CHECK
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------------
-- 6. Verify — expect 12 rows: 8 customer + 1 platform + mechanic + staff + driver
--    (the dual-role user contributes BOTH a customer and a mechanic row)
-- ---------------------------------------------------------------------------
SELECT m.scope, m.role, m.status, count(*) AS n
  FROM public.memberships m
 GROUP BY m.scope, m.role, m.status
 ORDER BY m.scope, m.role;
