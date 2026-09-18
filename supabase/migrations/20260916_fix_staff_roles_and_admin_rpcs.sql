-- =============================================================================
-- Migration: Fix Staff Roles & Admin User Management RPCs
-- Date: 2026-09-16
-- Fixes:
--   1. add_partner_staff missing search_path, void return hides failures
--   2. Missing remove_partner_staff RPC (direct UPDATE fails due to RLS)
--   3. Missing list_all_users RPC for admin central
--   4. Missing set_user_role RPC for admin central
--   5. Idempotent role CHECK constraint enforcement
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Idempotent: Ensure profiles.role CHECK constraint includes all 5 roles
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%role%';

    IF constraint_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || constraint_name;
    END IF;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('customer', 'partner_mechanic', 'master_admin', 'partner_staff', 'partner_driver'));


-- ---------------------------------------------------------------------------
-- 2. Fix add_partner_staff: proper search_path, returns JSON result
-- DROP first because we're changing return type void → JSONB
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.add_partner_staff(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.add_partner_staff(staff_email TEXT, staff_role TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_role TEXT;
    caller_partner_id UUID;
    target_user_id UUID;
    target_full_name TEXT;
    target_current_role TEXT;
BEGIN
    -- 1. Get caller's role from JWT metadata first
    SELECT raw_app_meta_data->>'role' INTO caller_role
    FROM auth.users
    WHERE id = auth.uid();

    -- Try to get partner_id from app_metadata or user_metadata
    SELECT COALESCE(
        raw_app_meta_data->>'partner_id',
        raw_user_meta_data->>'partner_id'
    )::uuid INTO caller_partner_id
    FROM auth.users
    WHERE id = auth.uid();

    -- Fallback to profiles if missing in auth.users
    IF caller_role IS NULL OR caller_partner_id IS NULL THEN
        SELECT
            COALESCE(caller_role, role),
            COALESCE(caller_partner_id, partner_id)
        INTO caller_role, caller_partner_id
        FROM public.profiles
        WHERE id = auth.uid();
    END IF;

    -- Allow master_admin OR partner_mechanic to add staff
    IF caller_role NOT IN ('partner_mechanic', 'master_admin') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Only workshop owners or admins can add staff. Your role: %s', caller_role)
        );
    END IF;

    IF caller_partner_id IS NULL AND caller_role = 'partner_mechanic' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'You are not associated with a valid partner workshop.'
        );
    END IF;

    IF staff_role NOT IN ('partner_staff', 'partner_driver') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Invalid staff role "%s". Must be partner_staff or partner_driver.', staff_role)
        );
    END IF;

    -- 2. Find the target user by email in auth.users
    SELECT id INTO target_user_id
    FROM auth.users
    WHERE email = staff_email;

    IF target_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('No account found with email "%s". They must register first.', staff_email)
        );
    END IF;

    -- 3. Check if they are already a partner_mechanic or master_admin
    SELECT role INTO target_current_role
    FROM public.profiles
    WHERE id = target_user_id;

    IF target_current_role IN ('partner_mechanic', 'master_admin') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Cannot assign staff role: user is already a %s.', target_current_role)
        );
    END IF;

    -- 4. Upsert into public.profiles
    INSERT INTO public.profiles (id, full_name, email, role, partner_id)
    VALUES (target_user_id, split_part(staff_email, '@', 1), staff_email, staff_role, caller_partner_id)
    ON CONFLICT (id) DO UPDATE
    SET role = staff_role,
        partner_id = caller_partner_id;

    -- 5. Update auth.users app_metadata with BOTH role and partner_id
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        jsonb_set(
            COALESCE(raw_app_meta_data, '{}'::jsonb),
            '{role}',
            to_jsonb(staff_role)
        ),
        '{partner_id}',
        to_jsonb(caller_partner_id::text)
    )
    WHERE id = target_user_id;

    -- 6. Get the name for the response
    SELECT full_name INTO target_full_name
    FROM public.profiles
    WHERE id = target_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', target_user_id,
        'full_name', COALESCE(target_full_name, split_part(staff_email, '@', 1)),
        'role', staff_role
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_partner_staff(TEXT, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. Create remove_partner_staff RPC
--    Reverts a staff/driver back to 'customer' and clears partner_id.
--    Only the owning partner_mechanic or master_admin can call this.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.remove_partner_staff(UUID);

CREATE OR REPLACE FUNCTION public.remove_partner_staff(target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_role TEXT;
    caller_partner_id UUID;
    target_partner_id UUID;
    target_role TEXT;
    target_name TEXT;
BEGIN
    -- Get caller info
    caller_role := (auth.jwt() -> 'app_metadata' ->> 'role');
    caller_partner_id := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid;

    -- Fallback to profiles
    IF caller_role IS NULL THEN
        SELECT role, partner_id INTO caller_role, caller_partner_id
        FROM public.profiles WHERE id = auth.uid();
    END IF;

    -- Auth check
    IF caller_role NOT IN ('partner_mechanic', 'master_admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    -- Get target info
    SELECT role, partner_id, full_name INTO target_role, target_partner_id, target_name
    FROM public.profiles WHERE id = target_user_id;

    IF target_role IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found');
    END IF;

    -- Only allow removing staff/driver roles
    IF target_role NOT IN ('partner_staff', 'partner_driver') THEN
        RETURN jsonb_build_object('success', false, 'error',
            format('User is a %s, not staff/driver.', target_role));
    END IF;

    -- Partner must own this staff member (admin can remove anyone)
    IF caller_role = 'partner_mechanic' AND caller_partner_id IS DISTINCT FROM target_partner_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'This staff member does not belong to your workshop.');
    END IF;

    -- Revert to customer
    UPDATE public.profiles
    SET role = 'customer', partner_id = NULL
    WHERE id = target_user_id;

    -- Update auth.users app_metadata
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
$$;

GRANT EXECUTE ON FUNCTION public.remove_partner_staff(UUID) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. Create list_all_users RPC for Admin Central
--    Joins auth.users with profiles to get full user information.
--    SECURITY DEFINER + is_master_admin() guard.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.list_all_users();

CREATE OR REPLACE FUNCTION public.list_all_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_master_admin() THEN
        RAISE EXCEPTION 'forbidden: admin role required';
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(row_data), '[]'::jsonb)
        FROM (
            SELECT jsonb_build_object(
                'id', u.id,
                'email', u.email,
                'display_name', COALESCE(p.full_name, split_part(u.email, '@', 1)),
                'full_name', p.full_name,
                'role', COALESCE(p.role, 'customer'),
                'partner_id', p.partner_id,
                'partner_name', par.shop_name,
                'phone', p.phone,
                'avatar_url', u.raw_user_meta_data->>'avatar_url',
                'created_at', u.created_at,
                'last_sign_in_at', u.last_sign_in_at,
                'app_metadata_role', u.raw_app_meta_data->>'role'
            ) AS row_data
            FROM auth.users u
            LEFT JOIN public.profiles p ON p.id = u.id
            LEFT JOIN public.partners par ON par.id = p.partner_id
            ORDER BY u.created_at DESC
        ) sub
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_all_users() TO authenticated;


-- ---------------------------------------------------------------------------
-- 5. Create set_user_role RPC for Admin Central
--    Updates both profiles.role and auth.users.raw_app_meta_data.
--    Handles partner_id linking for staff/driver roles.
--    SECURITY DEFINER + is_master_admin() guard.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.set_user_role(UUID, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.set_user_role(
    target_user_id UUID,
    new_role TEXT,
    new_partner_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old_role TEXT;
    v_user_email TEXT;
    v_full_name TEXT;
BEGIN
    IF NOT public.is_master_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'forbidden: admin role required');
    END IF;

    -- Validate role
    IF new_role NOT IN ('customer', 'partner_mechanic', 'master_admin', 'partner_staff', 'partner_driver') THEN
        RETURN jsonb_build_object('success', false, 'error',
            format('Invalid role "%s".', new_role));
    END IF;

    -- Prevent admin from demoting themselves
    IF target_user_id = auth.uid() AND new_role != 'master_admin' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot demote your own admin account.');
    END IF;

    -- Get current state
    SELECT p.role, p.full_name, u.email
    INTO v_old_role, v_full_name, v_user_email
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
    WHERE u.id = target_user_id;

    IF v_user_email IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found.');
    END IF;

    -- Require partner_id for partner-related roles
    IF new_role IN ('partner_staff', 'partner_driver') AND new_partner_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error',
            'partner_id is required when assigning staff/driver role.');
    END IF;

    -- Clear partner_id if moving to customer or master_admin
    IF new_role IN ('customer', 'master_admin') THEN
        new_partner_id := NULL;
    END IF;

    -- Upsert profiles
    INSERT INTO public.profiles (id, full_name, email, role, partner_id)
    VALUES (target_user_id, COALESCE(v_full_name, split_part(v_user_email, '@', 1)), v_user_email, new_role, new_partner_id)
    ON CONFLICT (id) DO UPDATE
    SET role = new_role,
        partner_id = new_partner_id;

    -- Update auth.users app_metadata
    IF new_partner_id IS NOT NULL THEN
        UPDATE auth.users
        SET raw_app_meta_data = jsonb_set(
            jsonb_set(
                COALESCE(raw_app_meta_data, '{}'::jsonb),
                '{role}',
                to_jsonb(new_role)
            ),
            '{partner_id}',
            to_jsonb(new_partner_id::text)
        )
        WHERE id = target_user_id;
    ELSE
        UPDATE auth.users
        SET raw_app_meta_data = (COALESCE(raw_app_meta_data, '{}'::jsonb) - 'partner_id')
                                || jsonb_build_object('role', new_role)
        WHERE id = target_user_id;
    END IF;

    -- Audit log
    INSERT INTO admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
        'SET_USER_ROLE',
        'profiles',
        target_user_id,
        auth.uid(),
        jsonb_build_object(
            'old_role', v_old_role,
            'new_role', new_role,
            'partner_id', new_partner_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'user_id', target_user_id,
        'old_role', v_old_role,
        'new_role', new_role,
        'email', v_user_email
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_role(UUID, TEXT, UUID) TO authenticated;
