-- Migration: Fix Add Staff RPC Caller Partner ID Validation

CREATE OR REPLACE FUNCTION public.add_partner_staff(staff_email TEXT, staff_role TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    caller_role TEXT;
    caller_partner_id UUID;
    target_user_id UUID;
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

    -- Fallbacks to profiles if missing in auth.users
    IF caller_role IS NULL OR caller_partner_id IS NULL THEN
        SELECT 
            COALESCE(caller_role, role), 
            COALESCE(caller_partner_id, partner_id) 
        INTO caller_role, caller_partner_id
        FROM public.profiles
        WHERE id = auth.uid();
    END IF;

    IF caller_role != 'partner_mechanic' THEN
        RAISE EXCEPTION 'Only workshop owners can add staff. Detected role: %, UID: %', caller_role, auth.uid();
    END IF;

    IF caller_partner_id IS NULL THEN
        RAISE EXCEPTION 'Caller is not associated with a valid partner workshop.';
    END IF;

    IF staff_role NOT IN ('partner_staff', 'partner_driver') THEN
        RAISE EXCEPTION 'Invalid staff role. Must be partner_staff or partner_driver.';
    END IF;

    -- 2. Find the target user by email in auth.users
    SELECT id INTO target_user_id
    FROM auth.users
    WHERE email = staff_email;

    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'User not found. They must register an account first.';
    END IF;

    -- 3. Upsert into public.profiles
    INSERT INTO public.profiles (id, full_name, email, role, partner_id)
    VALUES (target_user_id, split_part(staff_email, '@', 1), staff_email, staff_role, caller_partner_id)
    ON CONFLICT (id) DO UPDATE
    SET role = staff_role,
        partner_id = caller_partner_id;
    
    -- 4. Update auth.users app_metadata
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        COALESCE(raw_app_meta_data, '{}'::jsonb),
        '{role}',
        to_jsonb(staff_role)
    )
    WHERE id = target_user_id;

END;
$$;
