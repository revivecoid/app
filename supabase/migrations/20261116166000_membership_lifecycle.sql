-- Workshop staff could be added but never actually staff, and removal never
-- revoked access.
--
-- public.memberships was created with status CHECK IN ('active','invited',
-- 'suspended') and no updated_at column, while every RPC that touches it writes
-- status = 'inactive' and updated_at = now():
--   * add_partner_staff — `ON CONFLICT ... DO UPDATE SET status='active',
--     updated_at=now()` fails with 42703 on the re-add path, which aborts the
--     whole call before profiles.role is updated. The owner saw "Failed to add
--     staff member" and the person stayed a customer.
--   * remove_partner_staff — does not touch memberships at all, so the removed
--     user kept an active membership row and with it every partner policy.
--
-- Both fixed here: the vocabulary the SQL already writes is allowed, and
-- removal revokes the membership as well.

ALTER TABLE public.memberships
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS memberships_status_check;
ALTER TABLE public.memberships
  ADD CONSTRAINT memberships_status_check
  CHECK (status IN ('active', 'invited', 'suspended', 'inactive'));

-- Backfill: staff/driver profiles whose membership row never landed.
INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at, updated_at)
SELECT p.id,
       'partner'::public.membership_scope,
       p.partner_id,
       CASE p.role
         WHEN 'partner_driver'   THEN 'driver'::public.membership_role
         ELSE 'staff'::public.membership_role
       END,
       'active',
       now(),
       now()
  FROM public.profiles p
 WHERE p.role IN ('partner_staff', 'partner_driver')
   AND p.partner_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.memberships m
      WHERE m.user_id = p.id
        AND m.scope = 'partner'
        AND m.org_id = p.partner_id
        AND m.status = 'active'
   );

-- Removal must revoke the membership, not only the profile.
CREATE OR REPLACE FUNCTION public.remove_partner_staff(target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    caller_role TEXT;
    caller_partner_id UUID;
    target_partner_id UUID;
    target_role TEXT;
    target_name TEXT;
BEGIN
    caller_role := (auth.jwt() -> 'app_metadata' ->> 'role');
    caller_partner_id := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid;

    IF caller_role IS NULL THEN
        SELECT role, partner_id INTO caller_role, caller_partner_id
        FROM public.profiles WHERE id = auth.uid();
    END IF;

    IF caller_role NOT IN ('partner_mechanic', 'master_admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    SELECT role, partner_id, full_name INTO target_role, target_partner_id, target_name
    FROM public.profiles WHERE id = target_user_id;

    IF target_role IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found');
    END IF;

    IF target_role NOT IN ('partner_staff', 'partner_driver') THEN
        RETURN jsonb_build_object('success', false, 'error',
            format('User is a %s, not staff/driver.', target_role));
    END IF;

    IF caller_role = 'partner_mechanic' AND caller_partner_id IS DISTINCT FROM target_partner_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'This staff member does not belong to your workshop.');
    END IF;

    UPDATE public.memberships
       SET status = 'inactive',
           updated_at = now()
     WHERE user_id = target_user_id
       AND scope = 'partner';

    UPDATE public.profiles
       SET role = 'customer', partner_id = NULL
     WHERE id = target_user_id;

    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data - 'partner_id'
                            || jsonb_build_object('role', 'customer')
    WHERE id = target_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'removed_user', COALESCE(target_name, 'Unknown'),
        'previous_role', target_role
    );
END;
$function$;
