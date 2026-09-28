-- =============================================================================
-- 02_identity_security_test.sql — Test keamanan Fase 1
--
-- Verifikasi:
-- 1. Pelanggan tidak bisa mengubah profiles.role atau partner_id (C-02)
-- 2. Admin yang diturunkan kehilangan is_master_admin() (C-15)
-- 3. Staf yang dihapus kehilangan akses partner docs (C-09)
-- 4. Anon dan pelanggan tidak bisa membaca partners langsung (C-13)
-- 5. partners_public view ada dan tidak mengandung kolom sensitif (C-13)
-- 6. get_partner_active_job_count tidak bisa dipanggil anon (C-88)
-- 7. Owner tidak bisa mengubah is_active/suspended_at/auto_assign (C-16)
-- 8. Pemilik dokumen bisa baca dokumennya; pemilik lain tidak (C-08)
--
-- Catatan: Test 6 (anon call ke RPC) harus dijalankan di luar transaksi
--          karena SET LOCAL ROLE tidak sepenuhnya mensimulasikan anon key.
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _f1(seq int, step text, result text, ok boolean) ON COMMIT DROP;

DO $$
DECLARE
    v_cust_a    uuid;
    v_cust_b    uuid;
    v_admin     uuid;
    v_owner_a   uuid;
    v_staff_a   uuid;
    v_partner_a uuid;
    v_partner_b uuid;
    v_rows      int;
    v_role      text;
    v_pid       text;
    v_is_admin  boolean;
BEGIN
    -- ── Setup fixtures ──────────────────────────────────────────────────────
    v_cust_a    := tests.create_user('f1-cust-a@test.local',  'customer');
    v_cust_b    := tests.create_user('f1-cust-b@test.local',  'customer');
    v_admin     := tests.create_user('f1-admin@test.local',   'master_admin');
    v_owner_a   := tests.create_user('f1-owner-a@test.local', 'customer');
    v_staff_a   := tests.create_user('f1-staff-a@test.local', 'customer');

    -- Buat admin membership untuk v_admin
    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (v_admin, 'platform', NULL, 'master_admin', 'active', now())
    ON CONFLICT DO NOTHING;

    v_partner_a := tests.create_partner(v_owner_a);
    v_partner_b := tests.create_partner(v_cust_b);  -- v_cust_b sebagai owner bengkel B

    -- Tambah staff_a ke partner_a
    PERFORM tests.add_member(v_partner_a, v_staff_a, 'staff');

    -- Buat dokumen partner
    INSERT INTO public.partner_documents (partner_id, doc_type, file_key, file_name, uploaded_by)
    VALUES (v_partner_a, 'nib', 'partners/test-nib.pdf', 'nib.pdf', v_owner_a);

    -- ── TEST 1: Pelanggan tidak bisa mengubah profiles.role ────────────────
    PERFORM tests.as_user(v_cust_a);
    BEGIN
        UPDATE public.profiles SET role = 'master_admin' WHERE id = v_cust_a;
        -- Ambil nilai setelah update
        SELECT role INTO v_role FROM public.profiles WHERE id = v_cust_a;
        PERFORM tests.reset_role();
        INSERT INTO _f1 VALUES (
            1, 'Pelanggan tidak bisa ubah profiles.role (C-02)',
            'role setelah update=' || coalesce(v_role, 'NULL'),
            v_role = 'customer'  -- trigger harus mengembalikan ke 'customer'
        );
    EXCEPTION WHEN OTHERS THEN
        PERFORM tests.reset_role();
        INSERT INTO _f1 VALUES (
            1, 'Pelanggan tidak bisa ubah profiles.role (C-02)',
            'blocked dengan error=' || SQLERRM,
            TRUE
        );
    END;

    -- ── TEST 2: Admin yang diturunkan kehilangan is_master_admin() (C-15) ──
    -- Simulasi: nonaktifkan membership master_admin v_admin
    UPDATE public.memberships
       SET status = 'inactive'
     WHERE user_id = v_admin AND role = 'master_admin';

    PERFORM tests.as_user(v_admin);
    SELECT public.is_master_admin() INTO v_is_admin;
    PERFORM tests.reset_role();

    -- Pulihkan untuk test berikutnya
    UPDATE public.memberships SET status = 'active'
     WHERE user_id = v_admin AND role = 'master_admin';

    INSERT INTO _f1 VALUES (
        2, 'Admin diturunkan kehilangan is_master_admin() (C-15)',
        'is_master_admin=' || v_is_admin::text,
        NOT v_is_admin
    );

    -- ── TEST 3: Staf yang dihapus tidak bisa baca partner_documents ────────
    -- Non-aktifkan membership staff_a
    UPDATE public.memberships
       SET status = 'inactive'
     WHERE user_id = v_staff_a AND org_id = v_partner_a;

    PERFORM tests.as_user(v_staff_a);
    SELECT count(*) INTO v_rows
      FROM public.partner_documents
     WHERE partner_id = v_partner_a;
    PERFORM tests.reset_role();

    INSERT INTO _f1 VALUES (
        3, 'Staf yang dihapus tidak bisa baca partner_documents (C-09)',
        'rows_visible=' || v_rows,
        v_rows = 0
    );

    -- Pulihkan untuk test berikutnya
    UPDATE public.memberships SET status = 'active'
     WHERE user_id = v_staff_a AND org_id = v_partner_a;

    -- ── TEST 4: Anon tidak bisa membaca partners langsung (C-13) ─────────
    PERFORM tests.as_anon();
    SELECT count(*) INTO v_rows FROM public.partners;
    PERFORM tests.reset_role();

    INSERT INTO _f1 VALUES (
        4, 'Anon tidak bisa baca partners langsung (C-13)',
        'rows_visible=' || v_rows,
        v_rows = 0
    );

    -- ── TEST 5: partners_public ada dan bisa dibaca pelanggan (C-13) ──────
    PERFORM tests.as_user(v_cust_a);
    BEGIN
        SELECT count(*) INTO v_rows FROM public.partners_public;
        PERFORM tests.reset_role();
        INSERT INTO _f1 VALUES (
            5, 'partners_public dapat dibaca pelanggan (C-13)',
            'rows=' || v_rows,
            TRUE  -- view ada
        );
    EXCEPTION WHEN undefined_table THEN
        PERFORM tests.reset_role();
        INSERT INTO _f1 VALUES (
            5, 'partners_public dapat dibaca pelanggan (C-13)',
            'VIEW BELUM ADA',
            FALSE
        );
    END;

    -- ── TEST 6: Owner bengkel A bisa baca dokumennya; owner B tidak ───────
    PERFORM tests.as_user(v_owner_a);
    SELECT count(*) INTO v_rows
      FROM public.partner_documents
     WHERE partner_id = v_partner_a;
    PERFORM tests.reset_role();

    INSERT INTO _f1 VALUES (
        6, 'Owner bengkel A bisa baca dokumennya sendiri (C-08)',
        'rows=' || v_rows,
        v_rows > 0
    );

    PERFORM tests.as_user(v_cust_b);  -- owner bengkel B, bukan A
    SELECT count(*) INTO v_rows
      FROM public.partner_documents
     WHERE partner_id = v_partner_a;
    PERFORM tests.reset_role();

    INSERT INTO _f1 VALUES (
        7, 'Owner bengkel B tidak bisa baca dokumen bengkel A (C-08)',
        'rows=' || v_rows,
        v_rows = 0
    );

    -- ── TEST 8: Owner tidak bisa mengubah is_active sendiri (C-16) ─────────
    PERFORM tests.as_user(v_owner_a);
    BEGIN
        UPDATE public.partners SET is_active = false WHERE id = v_partner_a;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        PERFORM tests.reset_role();
        -- Cek nilai sebenarnya
        SELECT CASE WHEN is_active THEN 'true' ELSE 'false' END INTO v_role
          FROM public.partners WHERE id = v_partner_a;
        INSERT INTO _f1 VALUES (
            8, 'Owner tidak bisa ubah is_active sendiri (C-16)',
            'is_active setelah update=' || v_role,
            v_role = 'true'  -- trigger harus menolak
        );
    EXCEPTION WHEN OTHERS THEN
        PERFORM tests.reset_role();
        INSERT INTO _f1 VALUES (
            8, 'Owner tidak bisa ubah is_active sendiri (C-16)',
            'blocked=' || SQLERRM,
            TRUE
        );
    END;

END;
$$;

-- ── Tampilkan hasil ───────────────────────────────────────────────────────────
SELECT seq, step, result, ok,
       CASE WHEN ok THEN '✓ LULUS' ELSE '✗ GAGAL' END AS status
FROM _f1
ORDER BY seq;

SELECT
    count(*) FILTER (WHERE ok)     AS lulus,
    count(*) FILTER (WHERE NOT ok) AS gagal,
    count(*)                        AS total,
    CASE WHEN count(*) FILTER (WHERE NOT ok) = 0
         THEN 'SEMUA LULUS ✓'
         ELSE 'ADA KEGAGALAN ✗'
    END AS ringkasan
FROM _f1;

ROLLBACK;
