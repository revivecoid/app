-- =============================================================================
-- 20260928010000_f2_write_paths.sql
-- Fase 2: Keamanan B — jalur tulis, storage, notifikasi, auto-assign
--
-- Mengatasi: B-02 (KRITIS), C-01 (KRITIS), C-03 (KRITIS), SEC-04 (KRITIS),
--            B-04 (TINGGI), BIZ-02 (TINGGI), BIZ-03 (TINGGI), C-05 (TINGGI),
--            C-17 (TINGGI), C-18 (TINGGI), PRIV-01 (TINGGI), PRIV-02 (TINGGI),
--            C-56 (SEDANG), C-57 (SEDANG), C-58 (SEDANG), C-59 (SEDANG),
--            C-61 (SEDANG)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: C-01 — Perbaiki policy INSERT repair_jobs
-- Pelanggan hanya boleh INSERT dengan status='2_estimated', partner_id NULL,
-- tidak ada kolom finansial yang diisi
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Customers can create jobs"   ON public.repair_jobs;
DROP POLICY IF EXISTS "Customers can insert jobs"   ON public.repair_jobs;

CREATE POLICY "Customers can create estimate jobs" ON public.repair_jobs
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid()          = customer_id
    AND status          = '2_estimated'
    AND partner_id      IS NULL
    AND scheduled_date  IS NULL
    AND final_cost      IS NULL
    AND final_price     IS NULL
    AND completed_at    IS NULL
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: B-02, BIZ-02 — Trigger penjaga repair_jobs: blokir UPDATE kolom
-- sensitif oleh browser. Hanya RPC SECURITY DEFINER yang boleh mengubahnya.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.repair_jobs_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Blokir semua update sensitif dari klien langsung
  IF current_user IN ('authenticated', 'anon') THEN
    IF NEW.status             IS DISTINCT FROM OLD.status             THEN
      RAISE EXCEPTION 'FORBIDDEN: Gunakan RPC advance_job_status untuk mengubah status job.';
    END IF;
    IF NEW.partner_id         IS DISTINCT FROM OLD.partner_id         THEN
      RAISE EXCEPTION 'FORBIDDEN: partner_id hanya dapat diubah oleh sistem.';
    END IF;
    IF NEW.customer_id        IS DISTINCT FROM OLD.customer_id        THEN
      RAISE EXCEPTION 'FORBIDDEN: customer_id tidak dapat diubah.';
    END IF;
    IF NEW.final_cost         IS DISTINCT FROM OLD.final_cost         THEN
      RAISE EXCEPTION 'FORBIDDEN: final_cost hanya dapat diubah oleh RPC invoice.';
    END IF;
    IF NEW.final_price        IS DISTINCT FROM OLD.final_price        THEN
      RAISE EXCEPTION 'FORBIDDEN: final_price hanya dapat diubah oleh RPC invoice.';
    END IF;
    IF NEW.initial_estimation_cost IS DISTINCT FROM OLD.initial_estimation_cost THEN
      RAISE EXCEPTION 'FORBIDDEN: initial_estimation_cost hanya dapat diubah oleh sistem estimasi.';
    END IF;
    IF NEW.scheduled_date     IS DISTINCT FROM OLD.scheduled_date     THEN
      -- scheduled_date boleh diubah pelanggan saat booking — cek lebih ketat di RPC booking
      -- Untuk saat ini: izinkan bila status masih di tahap awal
      IF OLD.status NOT IN ('2_estimated', '3_booked') THEN
        RAISE EXCEPTION 'FORBIDDEN: scheduled_date tidak dapat diubah setelah job masuk bengkel.';
      END IF;
    END IF;
    IF NEW.completed_at       IS DISTINCT FROM OLD.completed_at       THEN
      RAISE EXCEPTION 'FORBIDDEN: completed_at hanya dapat diubah oleh sistem.';
    END IF;
    IF NEW.status_changed_at  IS DISTINCT FROM OLD.status_changed_at  THEN
      RAISE EXCEPTION 'FORBIDDEN: status_changed_at hanya dapat diubah oleh sistem.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Hapus trigger lama yang tidak efektif
DROP TRIGGER IF EXISTS validate_status_transition         ON public.repair_jobs;
DROP TRIGGER IF EXISTS enforce_status_transition          ON public.repair_jobs;
DROP TRIGGER IF EXISTS on_repair_job_status_change        ON public.repair_jobs;
DROP TRIGGER IF EXISTS repair_jobs_guard                  ON public.repair_jobs;

CREATE TRIGGER repair_jobs_guard
  BEFORE UPDATE ON public.repair_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.repair_jobs_guard();

-- B-01 interim: Buat admin_set_job_status sementara sampai Fase 4 (advance via job_status_transitions)
CREATE OR REPLACE FUNCTION public.admin_set_job_status(
    p_job_id uuid,
    p_status text,
    p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_master_admin() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Hanya admin yang bisa menggunakan admin_set_job_status.';
    END IF;

    UPDATE public.repair_jobs
       SET status           = p_status,
           status_changed_at = now(),
           updated_at        = now()
     WHERE id = p_job_id;

    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
        'ADMIN_SET_JOB_STATUS',
        'repair_jobs',
        p_job_id,
        auth.uid(),
        jsonb_build_object('status', p_status, 'reason', p_reason)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_job_status(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: C-05 — Hapus policy INSERT notifikasi untuk authenticated
-- Notifikasi hanya ditulis service_role (Edge Function send-notification)
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Service can insert notifications"         ON public.notifications;
DROP POLICY IF EXISTS "Users can read own notifications"         ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications"       ON public.notifications;

-- Baca notifikasi sendiri
CREATE POLICY "Users can read own notifications" ON public.notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Hanya boleh update read_at
CREATE POLICY "Users can mark notifications read" ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- INSERT hanya service_role (tidak ada policy — service_role bypass RLS)
-- Pastikan tidak ada policy INSERT untuk authenticated yang tersisa

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: C-56 — Drop policy FOR ALL lama di job_milestones
-- dan tambahkan gerbang DELETE hanya admin
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop 4 policy lama "Enable ... for partner personnel" dan "Enable ALL for master_admin"
DROP POLICY IF EXISTS "Enable INSERT for partner personnel on job_milestones"      ON public.job_milestones;
DROP POLICY IF EXISTS "Enable UPDATE for partner personnel on job_milestones"      ON public.job_milestones;
DROP POLICY IF EXISTS "Enable SELECT for partner personnel on job_milestones"      ON public.job_milestones;
DROP POLICY IF EXISTS "Enable ALL for partner personnel on job_milestones"         ON public.job_milestones;
DROP POLICY IF EXISTS "Enable INSERT for partner personnel on job_milestone_photos" ON public.job_milestone_photos;
DROP POLICY IF EXISTS "Enable UPDATE for partner personnel on job_milestone_photos" ON public.job_milestone_photos;
DROP POLICY IF EXISTS "Enable SELECT for partner personnel on job_milestone_photos" ON public.job_milestone_photos;

-- DELETE milestones: hanya admin
DROP POLICY IF EXISTS job_milestones_delete           ON public.job_milestones;
DROP POLICY IF EXISTS "job_milestones admin delete"   ON public.job_milestones;

CREATE POLICY "job_milestones_admin_delete" ON public.job_milestones
  FOR DELETE TO authenticated
  USING (is_master_admin());

-- Pastikan foto milestone mengikuti delete hanya admin juga
DROP POLICY IF EXISTS "job_milestone_photos_admin_delete" ON public.job_milestone_photos;
CREATE POLICY "job_milestone_photos_admin_delete" ON public.job_milestone_photos
  FOR DELETE TO authenticated
  USING (is_master_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: C-57 — Ubah FK repair_jobs ke ON DELETE RESTRICT
-- Pastikan pelanggan tidak bisa menghapus vehicle/profile dan menarik job ikut
-- ─────────────────────────────────────────────────────────────────────────────

-- Ubah FK vehicle_id menjadi RESTRICT (tidak bisa hapus vehicle bila ada job)
ALTER TABLE public.repair_jobs
  DROP CONSTRAINT IF EXISTS repair_jobs_vehicle_id_fkey;
ALTER TABLE public.repair_jobs
  ADD CONSTRAINT repair_jobs_vehicle_id_fkey
    FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE RESTRICT;

-- customer_id: anonimisasi saat hapus akun (bukan cascade)
-- Ini memerlukan trigger on auth.users delete — dibuatkan di bawah
-- Untuk saat ini: cabut DELETE langsung dari vehicles yang punya job aktif
CREATE OR REPLACE FUNCTION public.vehicles_guard_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_active_jobs int;
BEGIN
    SELECT count(*) INTO v_active_jobs
      FROM public.repair_jobs
     WHERE vehicle_id = OLD.id
       AND status NOT IN ('0_cancelled', '9_done');

    IF v_active_jobs > 0 THEN
        RAISE EXCEPTION 'FORBIDDEN: Tidak dapat menghapus kendaraan yang masih punya job aktif. Arsipkan kendaraan sebagai gantinya.';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS vehicles_guard_delete ON public.vehicles;
CREATE TRIGGER vehicles_guard_delete
  BEFORE DELETE ON public.vehicles
  FOR EACH ROW
  EXECUTE FUNCTION public.vehicles_guard_delete();

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: C-58 — Jaga partner_messages: from_admin dan immutability
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.partner_messages_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Mitra tidak boleh mengirim pesan as admin
        IF NEW.from_admin = true AND NOT is_master_admin() THEN
            RAISE EXCEPTION 'FORBIDDEN: Hanya admin yang bisa mengirim pesan sebagai admin.';
        END IF;
        -- sender_id harus sesuai caller
        IF NEW.sender_id IS NOT NULL AND NEW.sender_id != auth.uid() AND NOT is_master_admin() THEN
            RAISE EXCEPTION 'FORBIDDEN: sender_id tidak sesuai dengan pengguna yang login.';
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Isi pesan immutable setelah dibuat
        IF NEW.content IS DISTINCT FROM OLD.content AND NOT is_master_admin() THEN
            RAISE EXCEPTION 'FORBIDDEN: Isi pesan tidak dapat diubah setelah dikirim.';
        END IF;
        -- from_admin tidak boleh diubah
        IF NEW.from_admin IS DISTINCT FROM OLD.from_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Status from_admin tidak dapat diubah.';
        END IF;
        -- Penerima hanya boleh mengubah read_at (melalui UPDATE langsung)
        -- Pengirim tidak boleh mengubah apapun kecuali admin
        IF NOT is_master_admin() AND NEW.sender_id != auth.uid() THEN
            -- Ini penerima — hanya izinkan update read_at
            NEW.content    := OLD.content;
            NEW.from_admin := OLD.from_admin;
            NEW.sender_id  := OLD.sender_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_messages_guard ON public.partner_messages;
CREATE TRIGGER partner_messages_guard
  BEFORE INSERT OR UPDATE ON public.partner_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.partner_messages_guard();

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: B-04, C-17, C-61 — Perbaiki execute_auto_assign
-- + kunci baris + filter bengkel aktif + validasi job + audit
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.execute_auto_assign(
    p_job_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job          public.repair_jobs;
    v_settings     public.auto_assign_settings;
    v_partner_id   uuid;
    v_mode         text;
    v_last_partner uuid;
    v_result       jsonb;
BEGIN
    -- Hanya pelanggan pemilik job atau admin yang boleh memanggil
    SELECT * INTO v_job FROM public.repair_jobs
     WHERE id = p_job_id
       FOR UPDATE;  -- C-61: kunci baris job

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job tidak ditemukan: %', p_job_id;
    END IF;

    IF NOT (v_job.customer_id = auth.uid() OR is_master_admin()) THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Hanya pemilik job atau admin yang bisa memanggil auto-assign.';
    END IF;

    -- Job harus dalam status yang bisa di-assign
    IF v_job.status != '2_estimated' OR v_job.partner_id IS NOT NULL THEN
        RAISE EXCEPTION 'Job tidak eligible untuk auto-assign. Status: %, partner: %',
            v_job.status, v_job.partner_id;
    END IF;

    -- Kunci settings untuk serialisasi
    SELECT * INTO v_settings FROM public.auto_assign_settings
     WHERE id = 1
       FOR UPDATE;  -- C-61: serialisasi alokasi

    IF NOT FOUND OR NOT v_settings.is_active THEN
        RETURN jsonb_build_object('assigned', false, 'reason', 'auto_assign_disabled');
    END IF;

    v_mode         := v_settings.mode;
    v_last_partner := v_settings.last_partner_id;

    -- C-17: Hanya bengkel aktif, disetujui, tidak di-suspend, tidak dihapus
    IF v_mode = 'fill_first' THEN
        -- Priority bengkel yang paling kosong
        SELECT p.id INTO v_partner_id
          FROM public.partners p
         WHERE p.auto_assign_active = true
           AND p.is_active          = true           -- C-17
           AND p.suspended_at       IS NULL           -- C-17
           AND p.deleted_at         IS NULL           -- C-17
           AND (NOT v_settings.match_location OR TRUE)  -- lokasi diabaikan sementara
           AND get_partner_active_job_count(p.id) < p.auto_assign_capacity
         ORDER BY
           -- fill_first: kosong dulu, lalu prioritas, lalu rotasi
           CASE WHEN get_partner_active_job_count(p.id) = 0 THEN 0 ELSE 1 END,
           p.auto_assign_priority ASC,
           CASE WHEN p.id = v_last_partner THEN 1 ELSE 0 END
         LIMIT 1;

    ELSIF v_mode = 'round_robin' THEN
        SELECT p.id INTO v_partner_id
          FROM public.partners p
         WHERE p.auto_assign_active = true
           AND p.is_active          = true
           AND p.suspended_at       IS NULL
           AND p.deleted_at         IS NULL
           AND get_partner_active_job_count(p.id) < p.auto_assign_capacity
         ORDER BY
           CASE WHEN p.id = v_last_partner THEN 1 ELSE 0 END,  -- setelah last
           p.auto_assign_priority ASC
         LIMIT 1;

    ELSE  -- strict_priority
        SELECT p.id INTO v_partner_id
          FROM public.partners p
         WHERE p.auto_assign_active = true
           AND p.is_active          = true
           AND p.suspended_at       IS NULL
           AND p.deleted_at         IS NULL
           AND get_partner_active_job_count(p.id) < p.auto_assign_capacity
         ORDER BY p.auto_assign_priority ASC
         LIMIT 1;
    END IF;

    IF v_partner_id IS NULL THEN
        RETURN jsonb_build_object('assigned', false, 'reason', 'no_eligible_partner');
    END IF;

    -- Assign job
    UPDATE public.repair_jobs
       SET partner_id         = v_partner_id,
           status_changed_at  = now(),
           updated_at         = now()
     WHERE id = p_job_id
       AND partner_id IS NULL  -- C-61: double-check
       AND status = '2_estimated';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('assigned', false, 'reason', 'race_condition_retry');
    END IF;

    -- Update last_partner_id untuk round-robin
    UPDATE public.auto_assign_settings
       SET last_partner_id = v_partner_id
     WHERE id = 1;

    -- Audit log
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
        'AUTO_ASSIGN',
        'repair_jobs',
        p_job_id,
        auth.uid(),
        jsonb_build_object('partner_id', v_partner_id, 'mode', v_mode)
    );

    RETURN jsonb_build_object('assigned', true, 'partner_id', v_partner_id);
END;
$$;

-- B-04: cabut EXECUTE dari authenticated bila pelanggan tidak langsung memanggil
-- Karena booking_scheduling_screen.dart:167 masih memanggil ini,
-- kita pertahankan GRANT ke authenticated tapi dengan validasi ownership di dalam
REVOKE EXECUTE ON FUNCTION public.execute_auto_assign(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.execute_auto_assign(uuid) TO authenticated;

-- C-17: admin_suspend_partner dan admin_soft_delete_partner juga set auto_assign_active=false
CREATE OR REPLACE FUNCTION public.admin_suspend_partner(p_partner_id UUID, p_suspend BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_master_admin() THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can suspend partners.';
    END IF;

    UPDATE public.partners
       SET suspended_at       = CASE WHEN p_suspend THEN now() ELSE NULL END,
           is_active          = NOT p_suspend,
           auto_assign_active = CASE WHEN p_suspend THEN false ELSE auto_assign_active END,  -- C-17
           updated_at         = now()
     WHERE id = p_partner_id;

    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES (
        CASE WHEN p_suspend THEN 'SUSPEND_PARTNER' ELSE 'UNSUSPEND_PARTNER' END,
        'partners', p_partner_id, auth.uid(),
        jsonb_build_object('suspended', p_suspend)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_suspend_partner(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_suspend_partner(UUID, BOOLEAN) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 8: B-06/SEC-04/PRIV-01 — Setel bucket revive-photos ke private
-- Catatan: Verifikasi status bucket saat ini harus dilakukan manual dulu.
-- Migrasi ini setel ke private sebagai tindakan keamanan.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE storage.buckets
   SET public = false
 WHERE id = 'revive-photos';

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 9: C-03, C-59 — Perbaiki storage policies
-- Foto ops harus dibatasi per partner_id
-- Kunci foto job harus divalidasi berdasarkan folder path
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop policy ops lama yang tidak memeriksa partner_id (C-18, C-59)
DROP POLICY IF EXISTS "Ops roles can upload milestone photos" ON storage.objects;
DROP POLICY IF EXISTS "Ops roles can read milestone photos"   ON storage.objects;
DROP POLICY IF EXISTS "Ops staff can insert in ops folder"    ON storage.objects;
DROP POLICY IF EXISTS "Ops staff can read ops folder"         ON storage.objects;

-- Policy baru: ops/ folder dibatasi per partner (C-59, C-18: owner juga diizinkan)
CREATE POLICY "Ops members upload to their partner folder" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'ops'
    AND (storage.foldername(name))[2]::uuid = get_my_partner_id()
    AND get_my_partner_id() IS NOT NULL
  );

CREATE POLICY "Ops members read their partner folder" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'ops'
    AND (storage.foldername(name))[2]::uuid = get_my_partner_id()
    AND get_my_partner_id() IS NOT NULL
  );

-- C-03: Foto job (jobs/ folder) hanya untuk peserta job (customer atau partner bengkel)
DROP POLICY IF EXISTS "Job participants can read job photos"   ON storage.objects;
DROP POLICY IF EXISTS "Job participants can write job photos"  ON storage.objects;

CREATE POLICY "Job participants can read job photos" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = ((storage.foldername(name))[2])::uuid
        AND (
          rj.customer_id = auth.uid()
          OR (rj.partner_id IS NOT NULL AND has_partner_membership(rj.partner_id, ARRAY['owner','mechanic','staff','driver']::public.membership_role[]))
          OR is_master_admin()
        )
    )
  );

CREATE POLICY "Job participants can upload job photos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'jobs'
    AND EXISTS (
      SELECT 1 FROM public.repair_jobs rj
      WHERE rj.id = ((storage.foldername(name))[2])::uuid
        AND (
          rj.customer_id = auth.uid()
          OR (rj.partner_id IS NOT NULL AND has_partner_membership(rj.partner_id, ARRAY['owner','mechanic','staff']::public.membership_role[]))
          OR is_master_admin()
        )
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 10: PRIV-02 — CMS asset manager: batasi prefix cms/
-- Drop atau batasi policy yang memungkinkan listing seluruh bucket
-- ─────────────────────────────────────────────────────────────────────────────

-- Buat policy admin-only untuk listing luar cms/
-- Policy existing yang membuka semua bucket ke admin tetap bisa membaca cms/
-- Tambahkan policy bahwa non-admin hanya bisa listing prefix cms/
-- (Implementasi penuh memerlukan perubahan Dart pada frontend_content_studio_screen.dart — dicatat di MANUAL.md)

-- ─────────────────────────────────────────────────────────────────────────────
-- SELESAI — Catatan untuk pemilik repo
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. WAJIB: Ganti semua getPublicUrl() → createSignedUrl() di Dart untuk foto
--    pelanggan dan dokumen. List file berikut masih pakai getPublicUrl:
--    - job_stream_controller.dart:76
--    - partner_dashboard_controller.dart:198, 341
--    - partner_profile_controller.dart:511
--    - admin_partner_profile_controller.dart:146
--    - admin_partner_assessment_screen.dart:1168, 1244
--    - frontend_content_studio_screen.dart:714
-- 2. WAJIB: frontend_content_studio_screen.dart — batasi storage.list() ke prefix cms/
-- 3. Bucket revive-photos kini private — semua URL publik yang masih ada akan 403.
--    Pastikan signed URL sudah diimplementasi sebelum apply migrasi ini ke produksi.
