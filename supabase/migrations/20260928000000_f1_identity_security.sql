-- =============================================================================
-- 20260928000000_f1_identity_security.sql
-- Fase 1: Keamanan A — identitas, peran, dan keanggotaan
--
-- Mengatasi: B-03 (KRITIS), C-02 (KRITIS), SEC-02 (KRITIS),
--            B-05 (TINGGI), C-08 (TINGGI), C-09 (TINGGI), C-13 (TINGGI),
--            C-15 (TINGGI), C-16 (TINGGI), S-05 (TINGGI), SEC-06 (TINGGI),
--            SEC-08 (TINGGI), B-10 (SEDANG), C-45 (SEDANG), C-65 (SEDANG),
--            C-78 (RENDAH), C-88 (RENDAH)
--
-- PENTING: Setiap perubahan idempoten. Tidak mengedit migrasi lama.
-- Hanya menambah/mengganti policy dan fungsi melalui DROP IF EXISTS + CREATE.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 0: Perbaiki is_master_admin() — baca dari memberships, bukan profiles
-- (B-03, SEC-02: is_master_admin() masih bisa membaca profiles.role di
--  beberapa cabang karena authorization_consolidation berhenti di langkah 2/4)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_master_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
    WHERE user_id  = auth.uid()
      AND scope    = 'platform'
      AND role     = 'master_admin'
      AND status   = 'active'
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_master_admin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_master_admin() TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: Perbaiki get_my_partner_id() — baca dari memberships yang aktif
-- + pastikan bengkel aktif (B-05: suspend tidak mencabut akses)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_partner_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.org_id
  FROM public.memberships m
  JOIN public.partners p ON p.id = m.org_id
  WHERE m.user_id = auth.uid()
    AND m.scope   = 'partner'
    AND m.status  = 'active'
    AND p.is_active = true
    AND p.deleted_at IS NULL
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_partner_id() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_my_partner_id() TO authenticated, service_role;

-- Perbaiki has_partner_membership() juga — pastikan bengkel aktif (B-05)
CREATE OR REPLACE FUNCTION public.has_partner_membership(
    p_org_id uuid,
    p_roles  public.membership_role[]
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    JOIN public.partners p ON p.id = m.org_id
    WHERE m.user_id = auth.uid()
      AND m.org_id  = p_org_id
      AND m.role    = ANY(p_roles)
      AND m.status  = 'active'
      AND p.is_active = true
      AND p.deleted_at IS NULL
  );
$$;

REVOKE EXECUTE ON FUNCTION public.has_partner_membership(uuid, public.membership_role[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.has_partner_membership(uuid, public.membership_role[]) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: B-03 — Drop 7 policy user_metadata lama + buat ulang yang benar
-- Policies yang memakai user_metadata / app_metadata untuk otorisasi
-- ─────────────────────────────────────────────────────────────────────────────

-- 2a. repair_jobs — partner SELECT dan UPDATE
DROP POLICY IF EXISTS "Enable SELECT for partner personnel on repair_jobs" ON public.repair_jobs;
DROP POLICY IF EXISTS "Enable UPDATE for partner personnel on repair_jobs" ON public.repair_jobs;

CREATE POLICY "Partner members can read their jobs" ON public.repair_jobs
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR customer_id = auth.uid()
    OR (partner_id IS NOT NULL AND has_partner_membership(partner_id, ARRAY['owner','mechanic','staff','driver']::public.membership_role[]))
  );

-- UPDATE job oleh partner: hanya kolom operasional, bukan status/finansial (dijaga oleh trigger F2)
CREATE POLICY "Partner members can update their jobs (non-status)" ON public.repair_jobs
  FOR UPDATE TO authenticated
  USING (
    is_master_admin()
    OR (partner_id IS NOT NULL AND has_partner_membership(partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[]))
  );

-- 2b. partner_messages — admin dan partner (hapus user_metadata COALESCE)
DROP POLICY IF EXISTS "Master Admins can update partner messages" ON public.partner_messages;
DROP POLICY IF EXISTS "Partners can update their own messages"    ON public.partner_messages;

CREATE POLICY "Master Admins can update partner messages" ON public.partner_messages
  FOR UPDATE TO authenticated
  USING (is_master_admin());

CREATE POLICY "Partners can update their own messages" ON public.partner_messages
  FOR UPDATE TO authenticated
  USING (
    partner_id IS NOT NULL
    AND has_partner_membership(partner_id, ARRAY['owner','mechanic']::public.membership_role[])
  );

-- 2c. repair_photos — hapus policy lama yang pakai COALESCE user_metadata
DROP POLICY IF EXISTS "Enable SELECT for partner personnel on repair_photos" ON public.repair_photos;
DROP POLICY IF EXISTS "Enable INSERT for partner personnel on repair_photos" ON public.repair_photos;

-- Buat ulang: partner baca foto job mereka
CREATE POLICY "Partner members can read their job photos" ON public.repair_photos
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = repair_photos.job_id
        AND (
          rj.customer_id = auth.uid()
          OR (rj.partner_id IS NOT NULL AND has_partner_membership(rj.partner_id, ARRAY['owner','mechanic','staff','driver']::public.membership_role[]))
        )
    )
  );

CREATE POLICY "Partner members can insert job photos" ON public.repair_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    is_master_admin()
    OR EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = repair_photos.job_id
        AND rj.partner_id IS NOT NULL
        AND has_partner_membership(rj.partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[])
    )
  );

-- 2d. partner_documents — C-08: ganti partner_id = auth.uid() dengan has_partner_membership
DROP POLICY IF EXISTS "partner_docs_own_select" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_docs_own_insert" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_docs_own_update" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_docs_admin_all"  ON public.partner_documents;

CREATE POLICY "partner_docs_owner_select" ON public.partner_documents
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[])
  );

CREATE POLICY "partner_docs_owner_insert" ON public.partner_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner']::public.membership_role[])
  );

CREATE POLICY "partner_docs_owner_update" ON public.partner_documents
  FOR UPDATE TO authenticated
  USING (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner']::public.membership_role[])
  );

-- 2e. partner_facility_photos — sama dengan partner_documents
DROP POLICY IF EXISTS "partner_photos_own_select" ON public.partner_facility_photos;
DROP POLICY IF EXISTS "partner_photos_own_insert" ON public.partner_facility_photos;
DROP POLICY IF EXISTS "partner_photos_own_update" ON public.partner_facility_photos;
DROP POLICY IF EXISTS "partner_photos_admin_all"  ON public.partner_facility_photos;

CREATE POLICY "partner_photos_owner_select" ON public.partner_facility_photos
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[])
  );

CREATE POLICY "partner_photos_owner_insert" ON public.partner_facility_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[])
  );

CREATE POLICY "partner_photos_owner_update" ON public.partner_facility_photos
  FOR UPDATE TO authenticated
  USING (
    is_master_admin()
    OR has_partner_membership(partner_id, ARRAY['owner']::public.membership_role[])
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: C-02 — Kunci kolom sensitif profiles (role, partner_id)
-- Trigger BEFORE UPDATE yang menolak perubahan kolom sensitif oleh non-admin
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.profiles_lock_sensitive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Non-admin tidak boleh mengubah role atau partner_id
  IF current_user IN ('authenticated', 'anon') AND NOT public.is_master_admin() THEN
    NEW.id         := OLD.id;
    NEW.role       := OLD.role;
    NEW.partner_id := OLD.partner_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_lock_sensitive ON public.profiles;
CREATE TRIGGER profiles_lock_sensitive
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.profiles_lock_sensitive();

-- INSERT policy: pelanggan baru hanya boleh dengan role=customer, partner_id NULL
DROP POLICY IF EXISTS "Users can insert own profile"  ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile"  ON public.profiles;

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = id
    AND role = 'customer'
    AND partner_id IS NULL
  );

-- UPDATE: boleh update, tapi trigger akan mengabaikan role/partner_id
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: C-13 — partners_select: batasi kolom sensitif, buat partners_public
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop policy lama yang membuka semua kolom ke semua authenticated
DROP POLICY IF EXISTS partners_select               ON public.partners;
DROP POLICY IF EXISTS "Master Admins can read all partners" ON public.partners;

-- Policy baru: admin baca semua; anggota bengkel baca bengkelnya sendiri
CREATE POLICY "partners_admin_or_own" ON public.partners
  FOR SELECT TO authenticated
  USING (
    is_master_admin()
    OR id = get_my_partner_id()
  );

-- View publik untuk pelanggan dan tamu (tanpa kolom sensitif)
DROP VIEW IF EXISTS public.partners_public;
CREATE VIEW public.partners_public
  SECURITY INVOKER
AS
  SELECT
    id,
    shop_name,
    address,
    is_active,
    tier,
    -- kolom aman lainnya
    created_at
  FROM public.partners
  WHERE is_active = true
    AND deleted_at IS NULL;

-- Grant ke anon dan authenticated
GRANT SELECT ON public.partners_public TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: C-15 — set_user_role: cabut membership platform saat demosi admin
-- Baca fungsi dari pg_proc dan tambahkan logika cabut membership platform
-- ─────────────────────────────────────────────────────────────────────────────

-- Baca definisi fungsi dari live DB sebelum menimpa (dilakukan via CREATE OR REPLACE)
-- Menambahkan: DELETE memberships platform saat new_role != 'master_admin'

CREATE OR REPLACE FUNCTION public.set_user_role(
    p_target_user uuid,
    p_new_role    text,
    p_org_id      uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_scope      text;
    v_membership_role public.membership_role;
BEGIN
    -- Hanya admin yang bisa memanggil ini
    IF NOT is_master_admin() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can set user roles.';
    END IF;

    -- Tentukan scope dan role membership
    IF p_new_role = 'master_admin' THEN
        v_scope := 'platform'; v_membership_role := 'master_admin';
    ELSIF p_new_role = 'customer' THEN
        v_scope := 'platform'; v_membership_role := 'customer';
    ELSIF p_new_role IN ('partner_mechanic', 'owner') THEN
        v_scope := 'partner';  v_membership_role := 'owner';
    ELSIF p_new_role IN ('partner_staff', 'staff') THEN
        v_scope := 'partner';  v_membership_role := 'staff';
    ELSIF p_new_role IN ('partner_driver', 'driver') THEN
        v_scope := 'partner';  v_membership_role := 'driver';
    ELSE
        RAISE EXCEPTION 'Unknown role: %', p_new_role;
    END IF;

    -- C-15: Selalu cabut membership master_admin bila new_role bukan master_admin
    IF p_new_role != 'master_admin' THEN
        UPDATE public.memberships
           SET status = 'inactive'
         WHERE user_id = p_target_user
           AND scope   = 'platform'
           AND role    = 'master_admin';
    END IF;

    -- Cabut membership partner lama bila pindah bengkel atau jadi customer/admin
    IF v_scope = 'platform' OR (v_scope = 'partner' AND p_org_id IS NOT NULL) THEN
        UPDATE public.memberships
           SET status = 'inactive'
         WHERE user_id = p_target_user
           AND scope   = 'partner'
           AND (p_org_id IS NULL OR org_id != p_org_id);  -- cabut semua kecuali bengkel baru
    END IF;

    -- Tulis membership baru
    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (
        p_target_user,
        v_scope,
        CASE WHEN v_scope = 'partner' THEN p_org_id ELSE NULL END,
        v_membership_role,
        'active',
        now()
    )
    ON CONFLICT (user_id, scope, COALESCE(org_id, '00000000-0000-0000-0000-000000000000'::uuid), role)
    DO UPDATE SET status = 'active', updated_at = now();

    -- Update profiles.role dan app_metadata (cache tampilan klien — bukan sumber otorisasi)
    UPDATE public.profiles
       SET role = CASE
                    WHEN p_new_role = 'master_admin' THEN 'master_admin'
                    WHEN v_scope = 'partner' THEN 'partner_mechanic'  -- cache lama
                    ELSE 'customer'
                  END,
           partner_id = CASE WHEN v_scope = 'partner' THEN p_org_id ELSE NULL END
     WHERE id = p_target_user;

    -- Update app_metadata via admin API tidak bisa dilakukan dari SQL langsung
    -- (dilakukan oleh approve-partner / Edge Function — dicatat sebagai catatan untuk F8)

    -- Audit log
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
        'SET_USER_ROLE',
        'users',
        p_target_user,
        auth.uid(),
        jsonb_build_object('new_role', p_new_role, 'org_id', p_org_id)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_user_role(uuid, text, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_user_role(uuid, text, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: C-09 — add_partner_staff / remove_partner_staff menulis memberships
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.add_partner_staff(
    p_staff_email text,
    p_staff_role  text DEFAULT 'partner_staff'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_partner_id   uuid;
    v_target_id    uuid;
    v_target_scope text;
    v_role         public.membership_role;
BEGIN
    -- Dapatkan partner_id pemanggil
    v_partner_id := get_my_partner_id();
    IF v_partner_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only partner owners can add staff.';
    END IF;

    -- Pastikan pemanggil adalah owner (bukan staff biasa)
    IF NOT has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the workshop owner can add staff.';
    END IF;

    -- C-78: Normalisasi email (case-insensitive)
    -- Cari akun berdasarkan email — pesan error generik bila tidak ditemukan
    SELECT id INTO v_target_id
      FROM auth.users
     WHERE lower(trim(email)) = lower(trim(p_staff_email))
     LIMIT 1;

    -- Pesan error sama untuk "tidak ditemukan" dan "tidak eligible"
    -- agar tidak membocorkan keberadaan email
    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'Akun tidak dapat ditambahkan. Pastikan mereka sudah mendaftar dan coba lagi.';
    END IF;

    -- C-45: Jangan izinkan memindahkan akun yang sudah punya membership partner lain atau admin
    IF EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = v_target_id
          AND status  = 'active'
          AND (
              -- admin tidak boleh dipindahkan
              (scope = 'platform' AND role = 'master_admin')
              -- staf bengkel lain tidak boleh diambil
              OR (scope = 'partner' AND org_id != v_partner_id)
          )
    ) THEN
        RAISE EXCEPTION 'Akun tidak dapat ditambahkan. Pastikan mereka sudah mendaftar dan coba lagi.';
    END IF;

    -- Tentukan role membership
    IF p_staff_role IN ('partner_driver', 'driver') THEN
        v_role := 'driver'::public.membership_role;
    ELSE
        v_role := 'staff'::public.membership_role;
    END IF;

    -- Tulis membership
    INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
    VALUES (v_target_id, 'partner', v_partner_id, v_role, 'active', now())
    ON CONFLICT (user_id, scope, COALESCE(org_id, '00000000-0000-0000-0000-000000000000'::uuid), role)
    DO UPDATE SET status = 'active', updated_at = now();

    -- Update profiles cache (bukan sumber otorisasi)
    UPDATE public.profiles
       SET role = p_staff_role, partner_id = v_partner_id
     WHERE id = v_target_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_partner_staff(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.add_partner_staff(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_partner_staff(
    p_staff_email text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_partner_id uuid;
    v_target_id  uuid;
BEGIN
    v_partner_id := get_my_partner_id();
    IF v_partner_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only partner owners can remove staff.';
    END IF;

    IF NOT has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the workshop owner can remove staff.';
    END IF;

    -- C-78: Normalisasi email
    SELECT id INTO v_target_id
      FROM auth.users
     WHERE lower(trim(email)) = lower(trim(p_staff_email))
     LIMIT 1;

    IF v_target_id IS NULL THEN
        RETURN;  -- Senyap — tidak bocorkan keberadaan email
    END IF;

    -- Nonaktifkan membership partner — bukan hapus, agar bisa diaudit
    UPDATE public.memberships
       SET status = 'inactive', updated_at = now()
     WHERE user_id = v_target_id
       AND scope   = 'partner'
       AND org_id  = v_partner_id;

    -- Kembalikan profile ke customer
    UPDATE public.profiles
       SET role = 'customer', partner_id = NULL
     WHERE id = v_target_id
       AND partner_id = v_partner_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_partner_staff(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.remove_partner_staff(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: C-16 — Batasi UPDATE partners (trigger: tolak kolom sensitif)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.partners_guard_sensitive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Hanya admin dan service_role yang boleh mengubah kolom sensitif
  IF current_user NOT IN ('service_role', 'postgres', 'supabase_admin')
     AND NOT public.is_master_admin()
  THEN
    IF NEW.is_active        IS DISTINCT FROM OLD.is_active        THEN
      RAISE EXCEPTION 'FORBIDDEN: is_active hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.suspended_at     IS DISTINCT FROM OLD.suspended_at     THEN
      RAISE EXCEPTION 'FORBIDDEN: suspended_at hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.deleted_at       IS DISTINCT FROM OLD.deleted_at       THEN
      RAISE EXCEPTION 'FORBIDDEN: deleted_at hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.tier             IS DISTINCT FROM OLD.tier             THEN
      RAISE EXCEPTION 'FORBIDDEN: tier hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.commission_rate  IS DISTINCT FROM OLD.commission_rate  THEN
      RAISE EXCEPTION 'FORBIDDEN: commission_rate hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.auto_assign_active   IS DISTINCT FROM OLD.auto_assign_active   THEN
      RAISE EXCEPTION 'FORBIDDEN: auto_assign_active hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.auto_assign_priority IS DISTINCT FROM OLD.auto_assign_priority THEN
      RAISE EXCEPTION 'FORBIDDEN: auto_assign_priority hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.auto_assign_capacity IS DISTINCT FROM OLD.auto_assign_capacity THEN
      RAISE EXCEPTION 'FORBIDDEN: auto_assign_capacity hanya dapat diubah oleh admin.';
    END IF;
    IF NEW.approval_status  IS DISTINCT FROM OLD.approval_status  THEN
      RAISE EXCEPTION 'FORBIDDEN: approval_status hanya dapat diubah oleh admin.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partners_guard_sensitive ON public.partners;
CREATE TRIGGER partners_guard_sensitive
  BEFORE UPDATE ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION public.partners_guard_sensitive();

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 8: B-10 — Batasi ai_config: api_key_env dan api_base_url
-- ─────────────────────────────────────────────────────────────────────────────

-- CHECK constraint: api_key_env hanya dari nama secret AI yang valid
-- Tidak boleh SUPABASE_SERVICE_ROLE_KEY atau variabel sistem lain
ALTER TABLE public.ai_config
  DROP CONSTRAINT IF EXISTS ai_config_api_key_env_safe;

ALTER TABLE public.ai_config
  ADD CONSTRAINT ai_config_api_key_env_safe
    CHECK (
      api_key_env IS NULL
      OR (
        api_key_env ~ '^[A-Z][A-Z0-9_]*_KEY$'
        AND api_key_env NOT IN (
          'SUPABASE_SERVICE_ROLE_KEY',
          'SUPABASE_ANON_KEY',
          'SUPABASE_DB_PASSWORD',
          'SUPABASE_JWT_SECRET'
        )
      )
    );

-- CHECK constraint: api_base_url hanya dari host penyedia AI yang diizinkan
ALTER TABLE public.ai_config
  DROP CONSTRAINT IF EXISTS ai_config_api_base_url_safe;

ALTER TABLE public.ai_config
  ADD CONSTRAINT ai_config_api_base_url_safe
    CHECK (
      api_base_url ~ '^https://(generativelanguage\.googleapis\.com|api\.groq\.com|openrouter\.ai|api\.openai\.com|[a-zA-Z0-9-]+\.onrender\.com|[a-zA-Z0-9-]+\.reyhanzz\.xyz|[a-zA-Z0-9-]+\.bansosai\.app|localhost(:[0-9]+)?|127\.0\.0\.1(:[0-9]+)?)'
    );
    );

-- Policy ai_config: hapus yang pakai profiles/user_metadata, ganti ke is_master_admin()
DROP POLICY IF EXISTS "Master admin can manage ai_config"     ON public.ai_config;
DROP POLICY IF EXISTS "Authenticated users can read ai_config" ON public.ai_config;

CREATE POLICY "Master admin can manage ai_config" ON public.ai_config
  FOR ALL TO authenticated
  USING (is_master_admin())
  WITH CHECK (is_master_admin());

CREATE POLICY "Authenticated users can read ai_config" ON public.ai_config
  FOR SELECT TO authenticated
  USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 9: C-88 — get_partner_active_job_count: tambah search_path + revoke anon
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_partner_active_job_count(p_partner_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::INTEGER
  FROM public.repair_jobs
  WHERE partner_id = p_partner_id
    AND status IN ('2_estimated', '3_booked', '5_admitted', '3_inspected', '4_paid', '6_in_progress', '7_finished', '8_awaiting_delivery');
$$;

-- Revoke dari public/anon — hanya dipakai internal oleh execute_auto_assign
REVOKE EXECUTE ON FUNCTION public.get_partner_active_job_count(UUID) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_partner_active_job_count(UUID) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 10: S-05 — Backfill kosakata peran: partner_mechanic → owner
-- Pengguna yang ada sebagai 'mechanic' tapi seharusnya 'owner'
-- ─────────────────────────────────────────────────────────────────────────────

-- Setiap bengkel: pastikan pembuat/pemilik (partners.user_id) punya membership 'owner'
-- Bila ada membership 'mechanic' untuk user yang sama, non-aktifkan yang mechanic
DO $$
DECLARE
    v_rec RECORD;
BEGIN
    FOR v_rec IN
        SELECT p.id AS partner_id, p.user_id
        FROM public.partners p
        WHERE p.user_id IS NOT NULL
          AND p.deleted_at IS NULL
    LOOP
        -- Pastikan ada membership owner
        INSERT INTO public.memberships (user_id, scope, org_id, role, status, created_at)
        VALUES (v_rec.user_id, 'partner', v_rec.partner_id, 'owner', 'active', now())
        ON CONFLICT (user_id, scope, COALESCE(org_id, '00000000-0000-0000-0000-000000000000'::uuid), role)
        DO UPDATE SET status = 'active';

        -- Non-aktifkan duplikat mechanic untuk user yang sama di bengkel yang sama
        UPDATE public.memberships
           SET status = 'inactive'
         WHERE user_id = v_rec.user_id
           AND scope   = 'partner'
           AND org_id  = v_rec.partner_id
           AND role    = 'mechanic'
           AND status  = 'active';
    END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 11: C-65 — approve-partner: jangan timpa akun yang sudah ada
-- (Catatan: ini adalah logika Edge Function — catat untuk manual di F8)
-- ─────────────────────────────────────────────────────────────────────────────
-- Fungsi guard: cek apakah email sudah milik akun non-customer sebelum approve
CREATE OR REPLACE FUNCTION public.check_partner_approval_safe(
    p_email text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid   uuid;
    v_role  text;
BEGIN
    SELECT u.id, p.role INTO v_uid, v_role
      FROM auth.users u
      JOIN public.profiles p ON p.id = u.id
     WHERE lower(trim(u.email)) = lower(trim(p_email))
     LIMIT 1;

    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('safe', true, 'reason', 'new_account');
    END IF;

    -- Tolak bila akun sudah admin atau sudah punya partner membership aktif
    IF EXISTS (
        SELECT 1 FROM public.memberships
        WHERE user_id = v_uid
          AND status  = 'active'
          AND (
              (scope = 'platform' AND role = 'master_admin')
              OR scope = 'partner'
          )
    ) THEN
        RETURN jsonb_build_object(
            'safe', false,
            'reason', 'account_has_conflicting_role',
            'user_id', v_uid
        );
    END IF;

    RETURN jsonb_build_object('safe', true, 'user_id', v_uid, 'reason', 'existing_customer');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_partner_approval_safe(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.check_partner_approval_safe(text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- SELESAI — Verifikasi
-- ─────────────────────────────────────────────────────────────────────────────
-- Jalankan query ini untuk verifikasi setelah migrasi:
--
-- 1. Pastikan tidak ada policy yang masih pakai user_metadata:
-- SELECT schemaname, tablename, policyname
-- FROM pg_policies
-- WHERE coalesce(qual,'') || coalesce(with_check,'') ~* 'user_metadata';
--
-- 2. Pastikan get_partner_active_job_count tidak bisa dipanggil anon:
-- SELECT grantee FROM information_schema.routine_privileges
-- WHERE routine_name = 'get_partner_active_job_count' AND grantee IN ('anon','authenticated');
--
-- 3. Pastikan is_master_admin membaca memberships:
-- SELECT pg_get_functiondef(oid) FROM pg_proc
-- WHERE proname = 'is_master_admin' AND pronamespace = 'public'::regnamespace;
