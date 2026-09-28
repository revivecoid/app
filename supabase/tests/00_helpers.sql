-- =============================================================================
-- 00_helpers.sql — pgTAP helper schema untuk remediasi revivecoid/app
--
-- Catatan: Repo ini tidak menggunakan pgTAP extension secara resmi.
-- Helper ini menyediakan fungsi utilitas untuk test SQL di supabase/tests/.
-- Setiap test membungkus kerjanya dalam BEGIN...ROLLBACK agar tidak ada efek samping.
--
-- Cara pakai:
--   Setiap berkas test di-include setelah file ini di-execute.
--   Semua fungsi di skema `tests` dibuat sebagai SECURITY DEFINER
--   agar bisa mensimulasikan JWT dan peran yang berbeda.
-- =============================================================================

-- Skema tests untuk memisahkan helper dari skema public
CREATE SCHEMA IF NOT EXISTS tests;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.create_user
-- Membuat baris auth.users + profiles + memberships customer secara konsisten.
-- Mengembalikan uuid user yang baru dibuat.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.create_user(
    p_email       text,
    p_role        public.membership_role DEFAULT 'customer'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid   uuid := gen_random_uuid();
    v_now   timestamptz := now();
BEGIN
    -- auth.users minimal row
    INSERT INTO auth.users (
        id, aud, role, email, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        is_super_admin, created_at, updated_at,
        instance_id, confirmation_sent_at
    ) VALUES (
        v_uid, 'authenticated', 'authenticated',
        lower(trim(p_email)), v_now,
        jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
        '{}'::jsonb,
        false, v_now, v_now,
        '00000000-0000-0000-0000-000000000000', v_now
    );

    -- profiles row (handle_new_user trigger mungkin tidak aktif di test env)
    INSERT INTO public.profiles (id, email, full_name, role, created_at)
    VALUES (v_uid, lower(trim(p_email)), 'Test ' || p_email, p_role, v_now)
    ON CONFLICT (id) DO NOTHING;

    -- membership platform
    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (v_uid, 'platform', NULL, p_role, 'active', v_now)
    ON CONFLICT DO NOTHING;

    RETURN v_uid;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.create_partner
-- Membuat partners + membership owner untuk pengguna yang diberikan.
-- Mengembalikan uuid partner yang baru dibuat.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.create_partner(
    p_owner uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pid   uuid := gen_random_uuid();
    v_now   timestamptz := now();
BEGIN
    INSERT INTO public.partners (
        id, user_id, shop_name, entity_name, owner_name,
        email, phone, address, is_active, created_at, updated_at
    ) VALUES (
        v_pid, p_owner,
        'Test Partner ' || left(v_pid::text, 8),
        'PT Test', 'Test Owner',
        'partner-' || left(v_pid::text, 8) || '@test.local',
        '081200000000', 'Jl. Test No. 1',
        true, v_now, v_now
    );

    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (p_owner, 'partner', v_pid, 'owner', 'active', v_now)
    ON CONFLICT DO NOTHING;

    RETURN v_pid;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.add_member
-- Menambahkan membership mitra untuk pengguna yang sudah ada.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.add_member(
    p_partner   uuid,
    p_user      uuid,
    p_role      public.membership_role DEFAULT 'staff'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (p_user, 'partner', p_partner, p_role, 'active', now())
    ON CONFLICT DO NOTHING;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.create_job
-- Membuat repair_job sebagai superuser (melewati RLS) untuk setup skenario.
-- Mengembalikan uuid job yang baru dibuat.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.create_job(
    p_customer  uuid,
    p_status    text    DEFAULT '2_estimated',
    p_partner   uuid    DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_jid   uuid := gen_random_uuid();
    v_vid   uuid;
    v_now   timestamptz := now();
BEGIN
    -- vehicle minimal
    v_vid := gen_random_uuid();
    INSERT INTO public.vehicles (id, user_id, make, model, license_plate, created_at)
    VALUES (v_vid, p_customer, 'Test', 'Car', 'TEST-' || upper(left(v_jid::text, 6)), v_now)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.repair_jobs (
        id, customer_id, vehicle_id, status, partner_id, created_at, updated_at
    ) VALUES (
        v_jid, p_customer, v_vid, p_status, p_partner, v_now, v_now
    );

    RETURN v_jid;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.as_user
-- Mensimulasikan JWT user authenticated (untuk RLS + SECURITY DEFINER).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.as_user(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object(
            'sub',  p_uid::text,
            'role', 'authenticated',
            'aud',  'authenticated'
        )::text,
        true
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.as_anon
-- Mensimulasikan sesi anonim.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.as_anon()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.as_service
-- Mensimulasikan service_role (melewati RLS).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.as_service()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    SET LOCAL ROLE service_role;
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- tests.reset_role
-- Mengembalikan ke superuser / postgres setelah impersonasi.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tests.reset_role()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Grant execute ke authenticated agar bisa dipanggil dari test yang sedang di role authenticated
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tests TO authenticated, anon, service_role;
GRANT USAGE ON SCHEMA tests TO authenticated, anon, service_role;
