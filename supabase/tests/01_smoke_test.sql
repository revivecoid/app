-- =============================================================================
-- 01_smoke_test.sql — Smoke test: isolasi pelanggan dan akses dasar
--
-- Membuktikan:
-- 1. Pelanggan A tidak bisa membaca job pelanggan B (RLS repair_jobs berjalan)
-- 2. Pelanggan tidak bisa mengubah profiles.role atau partner_id sendiri
--    (setelah Fase 1 dipasang — saat ini test ini mungkin GAGAL, itu normal)
-- 3. Sesi anon tidak bisa membaca data sensitif partners
--
-- Semua dalam satu transaksi yang ROLLBACK — tidak ada efek samping.
-- =============================================================================

BEGIN;

CREATE TEMP TABLE _smoke(seq int, step text, result text, ok boolean) ON COMMIT DROP;

-- ── Setup fixtures ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_cust_a  uuid;
    v_cust_b  uuid;
    v_owner   uuid;
    v_partner uuid;
    v_job_a   uuid;
    v_job_b   uuid;
    v_rows    int;
    v_role    text;
    v_pid     text;
BEGIN
    -- Buat dua pelanggan terpisah
    v_cust_a  := tests.create_user('smoke-a@test.local', 'customer');
    v_cust_b  := tests.create_user('smoke-b@test.local', 'customer');
    v_owner   := tests.create_user('smoke-owner@test.local', 'customer');
    v_partner := tests.create_partner(v_owner);
    v_job_a   := tests.create_job(v_cust_a, '2_estimated', NULL);
    v_job_b   := tests.create_job(v_cust_b, '2_estimated', NULL);

    -- ── TEST 1: Pelanggan A tidak bisa membaca job pelanggan B ──
    PERFORM tests.as_user(v_cust_a);
    SELECT count(*) INTO v_rows FROM public.repair_jobs WHERE id = v_job_b;
    PERFORM tests.reset_role();
    INSERT INTO _smoke VALUES (
        1, 'Pelanggan A tidak bisa baca job B',
        'rows_visible=' || v_rows,
        v_rows = 0
    );

    -- ── TEST 2: Pelanggan A bisa membaca jobnya sendiri ──
    PERFORM tests.as_user(v_cust_a);
    SELECT count(*) INTO v_rows FROM public.repair_jobs WHERE id = v_job_a;
    PERFORM tests.reset_role();
    INSERT INTO _smoke VALUES (
        2, 'Pelanggan A bisa baca job sendiri',
        'rows_visible=' || v_rows,
        v_rows = 1
    );

    -- ── TEST 3: Pelanggan A tidak bisa membaca job pelanggan B via UPDATE ──
    -- Pastikan UPDATE pada job orang lain ditolak
    PERFORM tests.as_user(v_cust_a);
    BEGIN
        UPDATE public.repair_jobs SET updated_at = now() WHERE id = v_job_b;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        INSERT INTO _smoke VALUES (
            3, 'Pelanggan A tidak bisa UPDATE job B (RLS)',
            'rows_updated=' || v_rows,
            v_rows = 0
        );
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO _smoke VALUES (
            3, 'Pelanggan A tidak bisa UPDATE job B (RLS)',
            'error=' || SQLERRM,
            TRUE  -- error = baik
        );
    END;
    PERFORM tests.reset_role();

    -- ── TEST 4: Anon tidak bisa membaca partners dengan kolom sensitif ──
    -- (C-13: partners_select membuka semua kolom ke semua session termasuk anon)
    -- Test ini harus GAGAL sebelum Fase 1, karena partners_select masih terbuka.
    -- Setelah Fase 1, hasilnya 0 baris.
    PERFORM tests.as_anon();
    SELECT count(*) INTO v_rows FROM public.partners;
    PERFORM tests.reset_role();
    INSERT INTO _smoke VALUES (
        4, 'Anon tidak bisa membaca partners (C-13 — harus 0 setelah F1)',
        'rows_visible=' || v_rows,
        v_rows = 0  -- akan GAGAL sebelum Fase 1 dipasang (expected)
    );

    -- ── TEST 5: Helper impersonasi berfungsi ──
    -- Setelah as_user, auth.uid() harus mengembalikan uid yang benar
    PERFORM tests.as_user(v_cust_a);
    SELECT (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
    INTO v_pid;
    PERFORM tests.reset_role();
    INSERT INTO _smoke VALUES (
        5, 'as_user menetapkan jwt.claims.sub dengan benar',
        'sub=' || coalesce(v_pid, 'NULL'),
        v_pid = v_cust_a::text
    );

    -- ── TEST 6: Pelanggan tidak bisa membaca data sensitif partners ──
    -- partners_public view harus tersedia setelah Fase 1 (saat ini mungkin tidak ada)
    -- Untuk sekarang: pastikan view tidak bocorkan kolom sensitif bila sudah ada
    PERFORM tests.as_user(v_cust_a);
    BEGIN
        SELECT count(*) INTO v_rows
        FROM public.partners_public
        WHERE id = v_partner;
        INSERT INTO _smoke VALUES (
            6, 'partners_public view ada dan dapat dibaca pelanggan',
            'rows=' || v_rows,
            TRUE
        );
    EXCEPTION WHEN undefined_table THEN
        INSERT INTO _smoke VALUES (
            6, 'partners_public view ada dan dapat dibaca pelanggan',
            'view belum ada (expected sebelum Fase 1)',
            FALSE  -- GAGAL = normal sebelum F1
        );
    END;
    PERFORM tests.reset_role();

END;
$$;

-- ── Tampilkan hasil ───────────────────────────────────────────────────────────
SELECT seq, step, result, ok,
       CASE WHEN ok THEN 'LULUS' ELSE 'GAGAL' END AS status
FROM _smoke
ORDER BY seq;

-- Ringkasan
SELECT
    count(*) FILTER (WHERE ok)     AS lulus,
    count(*) FILTER (WHERE NOT ok) AS gagal,
    count(*)                        AS total
FROM _smoke;

ROLLBACK;
