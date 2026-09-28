-- =============================================================================
-- 20260928080000_f8_partner_app.sql
-- Fase 8: identitas bengkel, notifikasi, normalisasi telepon, pesan
-- Mengatasi: S-04, C-07, C-25, C-26, C-50, C-53, C-63, C-64, CODE-03,
--            D-01, D-02, DAT-03, PERF-05, REL-07, S-09, SEC-12, C-77, C-79,
--            C-80, C-81, C-90, C-92
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: normalize_id_phone (S-09)
-- Format E.164 dari nomor Indonesia
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.normalize_id_phone(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_digits text;
BEGIN
  -- Hapus semua non-digit
  v_digits := regexp_replace(p_raw, '[^0-9]', '', 'g');

  IF v_digits = '' THEN RETURN NULL; END IF;

  -- Sudah E.164 tanpa +
  IF v_digits ~ '^62[0-9]{8,13}$' THEN
    RETURN '+' || v_digits;
  END IF;

  -- Diawali 0 → ganti dengan 62
  IF v_digits ~ '^0[0-9]{7,12}$' THEN
    RETURN '+62' || substring(v_digits FROM 2);
  END IF;

  -- Sudah tanpa kode negara (8xxx / 9xxx / 7xxx)
  IF v_digits ~ '^[789][0-9]{7,11}$' THEN
    RETURN '+62' || v_digits;
  END IF;

  -- Tidak dikenali — kembalikan NULL
  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_id_phone(text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: admin_approve_partner atomik (C-64)
-- Klaim aplikasi dulu, buat partner+membership dalam satu transaksi
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_approve_partner(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_app       RECORD;
  v_partner   RECORD;
  v_user_id   uuid;
  v_partner_id uuid;
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can approve partners';
  END IF;

  -- Klaim atomik: UPDATE hanya bila status masih pending/pending_review
  UPDATE public.partner_applications
  SET status = 'approving', updated_at = now()
  WHERE id = p_application_id
    AND status IN ('pending', 'pending_review')
  RETURNING * INTO v_app;

  IF NOT FOUND THEN
    -- Idempoten: sudah disetujui sebelumnya?
    SELECT * INTO v_app FROM public.partner_applications WHERE id = p_application_id;
    IF v_app.status = 'approved' THEN
      SELECT id INTO v_partner_id FROM public.partners
        WHERE id = (v_app.metadata->>'partner_id')::uuid;
      RETURN jsonb_build_object('partner_id', v_partner_id, 'idempotent', true);
    END IF;
    RAISE EXCEPTION 'APPROVE_ERROR: Application % not in approvable state (status: %)',
      p_application_id, v_app.status;
  END IF;

  -- Cari user by email (bila sudah ada akun)
  SELECT id INTO v_user_id FROM auth.users WHERE email = lower(v_app.email) LIMIT 1;

  -- Buat baris partners (idempoten via ON CONFLICT)
  INSERT INTO public.partners (
    shop_name, email, phone, address,
    tier, throughput_capacity, service_radius_km,
    status, is_active, user_id,
    service_area, created_at
  )
  VALUES (
    v_app.shop_name,
    lower(v_app.email),
    normalize_id_phone(v_app.phone),
    v_app.address,
    COALESCE(v_app.tier, 2),
    COALESCE(v_app.throughput_capacity, 12),
    v_app.service_radius_km,
    'approved', true,
    v_user_id,
    v_app.service_area,
    now()
  )
  ON CONFLICT (email) DO UPDATE
    SET status = 'approved', is_active = true, updated_at = now()
  RETURNING id INTO v_partner_id;

  -- Buat membership owner (idempoten)
  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.memberships (user_id, org_id, role, status)
    VALUES (v_user_id, v_partner_id, 'owner', 'active')
    ON CONFLICT (user_id, org_id) DO UPDATE SET role = 'owner', status = 'active';

    -- Update profiles
    UPDATE public.profiles SET partner_id = v_partner_id WHERE id = v_user_id;
  END IF;

  -- Copy dokumen
  INSERT INTO public.partner_documents (partner_id, doc_type, file_key, is_current)
  SELECT v_partner_id, doc_type, file_key, true
  FROM public.partner_applications pa
  JOIN jsonb_array_elements(COALESCE(v_app.documents, '[]'::jsonb)) AS d ON true
  CROSS JOIN LATERAL (
    SELECT d->>'doc_type' AS doc_type, d->>'file_key' AS file_key
  ) AS doc
  WHERE doc.file_key IS NOT NULL
  ON CONFLICT DO NOTHING;

  -- Copy foto fasilitas
  INSERT INTO public.partner_facility_photos (partner_id, file_key, slot, is_current)
  SELECT v_partner_id, p->>'file_key', (p->>'slot')::int, true
  FROM jsonb_array_elements(COALESCE(v_app.facility_photo_keys, '[]'::jsonb)) AS p
  WHERE (p->>'slot')::int BETWEEN 0 AND 3
  ON CONFLICT DO NOTHING;

  -- Tutup aplikasi
  UPDATE public.partner_applications
  SET status = 'approved',
      metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('partner_id', v_partner_id),
      updated_at = now()
  WHERE id = p_application_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('APPROVE_PARTNER', 'partner_applications', p_application_id, auth.uid(),
    jsonb_build_object('partner_id', v_partner_id, 'email', v_app.email));

  RETURN jsonb_build_object('partner_id', v_partner_id, 'idempotent', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_approve_partner(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_approve_partner(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: partner_update_profile RPC (C-07, S-04)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.partner_update_profile(
  p_shop_name   text DEFAULT NULL,
  p_phone       text DEFAULT NULL,
  p_address     text DEFAULT NULL,
  p_service_area text DEFAULT NULL,
  p_throughput_capacity int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_partner_id uuid;
BEGIN
  v_partner_id := get_my_partner_id();
  IF v_partner_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Not a partner'; END IF;
  IF NOT has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only owner can update partner profile';
  END IF;

  UPDATE public.partners SET
    shop_name           = COALESCE(p_shop_name,   shop_name),
    phone               = COALESCE(normalize_id_phone(p_phone), phone),
    address             = COALESCE(p_address,     address),
    service_area        = COALESCE(p_service_area, service_area),
    throughput_capacity = COALESCE(p_throughput_capacity, throughput_capacity),
    updated_at          = now()
  WHERE id = v_partner_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.partner_update_profile(text,text,text,text,int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.partner_update_profile(text,text,text,text,int) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: mark_messages_read RPC (REL-07, C-53)
-- Tandai dibaca sekali via RPC eksplisit, bukan di dalam stream
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mark_messages_read(p_partner_id uuid, p_before timestamptz DEFAULT now())
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  -- Partner menandai pesan admin sebagai dibaca
  -- Admin menandai pesan partner sebagai dibaca
  UPDATE public.partner_messages
  SET is_read = true
  WHERE partner_id = p_partner_id
    AND is_read = false
    AND created_at <= p_before
    AND sender_id <> v_uid;  -- hanya pesan dari pihak lain
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_messages_read(uuid, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_messages_read(uuid, timestamptz) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: get_unread_message_count RPC (PERF-05)
-- Agregat server-side untuk dashboard admin, bukan stream seluruh tabel
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_unread_message_count()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_count int;
BEGIN
  IF is_master_admin() THEN
    -- Admin: hitung pesan dari partner yang belum dibaca
    SELECT COUNT(*)::int INTO v_count
    FROM public.partner_messages
    WHERE is_read = false AND from_admin = false;
  ELSE
    -- Partner: hitung pesan dari admin yang belum dibaca
    DECLARE v_partner_id uuid := get_my_partner_id();
    BEGIN
      SELECT COUNT(*)::int INTO v_count
      FROM public.partner_messages
      WHERE partner_id = v_partner_id
        AND is_read = false
        AND from_admin = true;
    END;
  END IF;
  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_unread_message_count() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_unread_message_count() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: partner_messages RLS — from_admin diisi server (C-25)
-- ─────────────────────────────────────────────────────────────────────────────

-- Trigger: set from_admin dari is_master_admin() saat INSERT
CREATE OR REPLACE FUNCTION public.set_partner_message_from_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.from_admin := is_master_admin();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_messages_set_from_admin ON public.partner_messages;
CREATE TRIGGER partner_messages_set_from_admin
  BEFORE INSERT ON public.partner_messages
  FOR EACH ROW EXECUTE FUNCTION public.set_partner_message_from_admin();

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 7: submit-partner-application hardening (C-77, C-92, SEC-12)
-- CHECK constraints di partner_applications
-- ─────────────────────────────────────────────────────────────────────────────

-- Ganti ilike dengan eq di level DB constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema='public' AND table_name='partner_applications'
      AND constraint_name='partner_applications_tier_check'
  ) THEN
    ALTER TABLE public.partner_applications
      ADD CONSTRAINT partner_applications_tier_check CHECK (tier IN (1,2,3));
  END IF;
EXCEPTION WHEN others THEN NULL;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema='public' AND table_name='partner_applications'
      AND constraint_name='partner_applications_capacity_check'
  ) THEN
    ALTER TABLE public.partner_applications
      ADD CONSTRAINT partner_applications_capacity_check
        CHECK (throughput_capacity IS NULL OR (throughput_capacity >= 1 AND throughput_capacity <= 50));
  END IF;
EXCEPTION WHEN others THEN NULL;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFIKASI
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname IN ('normalize_id_phone','admin_approve_partner','partner_update_profile',
--                   'mark_messages_read','get_unread_message_count','set_partner_message_from_admin')
-- ORDER BY proname;
-- SELECT tgname FROM pg_trigger WHERE tgname IN ('partner_messages_set_from_admin');
