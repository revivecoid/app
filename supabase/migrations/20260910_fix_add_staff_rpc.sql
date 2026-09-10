-- Migration: Fix Add Staff RPC
-- Upgrades the RPC to look in auth.users in case the profiles row doesn't exist yet,
-- and upserts the profiles row.

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
    
    -- 4. Also update auth.users app_metadata to ensure JWT matches.
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        COALESCE(raw_app_meta_data, '{}'::jsonb),
        '{role}',
        to_jsonb(staff_role)
    )
    WHERE id = target_user_id;

END;
$$;
