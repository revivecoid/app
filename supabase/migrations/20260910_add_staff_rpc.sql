-- Migration: Add Staff RPC
-- Allows a partner_mechanic to assign an existing user to their workshop as staff or driver.

CREATE OR REPLACE FUNCTION public.add_partner_staff(staff_email TEXT, staff_role TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    caller_role TEXT;
    caller_partner_id UUID;
    target_profile_id UUID;
BEGIN
    -- 1. Get caller's role and partner_id
    SELECT role, partner_id INTO caller_role, caller_partner_id
    FROM public.profiles
    WHERE id = auth.uid();

    IF caller_role != 'partner_mechanic' THEN
        RAISE EXCEPTION 'Only workshop owners (partner_mechanic) can add staff.';
    END IF;

    IF caller_partner_id IS NULL THEN
        RAISE EXCEPTION 'Caller is not associated with a valid partner workshop.';
    END IF;

    IF staff_role NOT IN ('partner_staff', 'partner_driver') THEN
        RAISE EXCEPTION 'Invalid staff role. Must be partner_staff or partner_driver.';
    END IF;

    -- 2. Find the target user by email
    SELECT id INTO target_profile_id
    FROM public.profiles
    WHERE email = staff_email;

    IF target_profile_id IS NULL THEN
        RAISE EXCEPTION 'User not found. They must register an account first.';
    END IF;

    -- 3. Update the user
    UPDATE public.profiles
    SET role = staff_role,
        partner_id = caller_partner_id
    WHERE id = target_profile_id;
    
    -- Also update auth.users app_metadata to ensure JWT matches.
    -- Because this function is SECURITY DEFINER, it has permissions to do this if owner is postgres.
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        COALESCE(raw_app_meta_data, '{}'::jsonb),
        '{role}',
        to_jsonb(staff_role)
    )
    WHERE id = target_profile_id;

END;
$$;
