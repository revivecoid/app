-- =============================================================================
-- 20260928120000_f12_privacy_platform.sql
-- Fase 12: hak subjek data, persetujuan, FK aman
-- Mengatasi: C-86, PRIV-05, PRIV-06
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: FK aman (C-86)
-- Ubah FK uploaded_by/user_id/deleted_by/performed_by → ON DELETE SET NULL
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- partner_documents.uploaded_by
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='partner_documents' AND column_name='uploaded_by'
  ) THEN
    ALTER TABLE public.partner_documents DROP CONSTRAINT IF EXISTS partner_documents_uploaded_by_fkey;
    ALTER TABLE public.partner_documents
      ALTER COLUMN uploaded_by DROP NOT NULL;
    ALTER TABLE public.partner_documents
      ADD CONSTRAINT partner_documents_uploaded_by_fkey
        FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  -- partner_facility_photos.uploaded_by
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='partner_facility_photos' AND column_name='uploaded_by'
  ) THEN
    ALTER TABLE public.partner_facility_photos DROP CONSTRAINT IF EXISTS partner_facility_photos_uploaded_by_fkey;
    ALTER TABLE public.partner_facility_photos
      ALTER COLUMN uploaded_by DROP NOT NULL;
    ALTER TABLE public.partner_facility_photos
      ADD CONSTRAINT partner_facility_photos_uploaded_by_fkey
        FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  -- admin_audit_log.performed_by → SET NULL
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='admin_audit_log' AND column_name='performed_by'
  ) THEN
    ALTER TABLE public.admin_audit_log DROP CONSTRAINT IF EXISTS admin_audit_log_performed_by_fkey;
    ALTER TABLE public.admin_audit_log
      ALTER COLUMN performed_by DROP NOT NULL;
    ALTER TABLE public.admin_audit_log
      ADD CONSTRAINT admin_audit_log_performed_by_fkey
        FOREIGN KEY (performed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  -- partner_messages.sender_id → SET NULL (not CASCADE)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='partner_messages' AND column_name='sender_id'
  ) THEN
    ALTER TABLE public.partner_messages DROP CONSTRAINT IF EXISTS partner_messages_sender_id_fkey;
    ALTER TABLE public.partner_messages
      ALTER COLUMN sender_id DROP NOT NULL;
    ALTER TABLE public.partner_messages
      ADD CONSTRAINT partner_messages_sender_id_fkey
        FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'FK migration partial: %', SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: consents table (PRIV-06, UX-17)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.consents (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doc        text        NOT NULL CHECK (doc IN ('terms','privacy','estimation')),
  version    text        NOT NULL,
  given_at   timestamptz NOT NULL DEFAULT now(),
  ip_hint    text,
  UNIQUE (user_id, doc, version)
);

CREATE INDEX IF NOT EXISTS idx_consents_user ON public.consents(user_id);
ALTER TABLE public.consents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own consents" ON public.consents;
DROP POLICY IF EXISTS "Users insert own consents" ON public.consents;
CREATE POLICY "Users read own consents" ON public.consents FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_master_admin());
CREATE POLICY "Users insert own consents" ON public.consents FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: account_deletion_requests table (PRIV-05)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason       text,
  status       text        NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','processing','completed','rejected')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processed_by uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (user_id, status) -- one pending per user
);

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own deletion requests" ON public.account_deletion_requests;
CREATE POLICY "Users read own deletion requests" ON public.account_deletion_requests
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_master_admin());
CREATE POLICY "Admin manages deletion requests" ON public.account_deletion_requests
  FOR ALL TO authenticated USING (is_master_admin()) WITH CHECK (is_master_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: request_account_deletion RPC (PRIV-05)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.request_account_deletion(p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_req_id  uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Login required'; END IF;

  -- Idempoten: bila sudah ada permintaan pending, kembalikan yang ada
  SELECT id INTO v_req_id FROM public.account_deletion_requests
  WHERE user_id = v_user_id AND status = 'pending';
  IF FOUND THEN RETURN v_req_id; END IF;

  INSERT INTO public.account_deletion_requests (user_id, reason)
  VALUES (v_user_id, p_reason)
  RETURNING id INTO v_req_id;

  -- Notifikasi ke admin
  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('ACCOUNT_DELETION_REQUESTED', 'auth.users', v_user_id, v_user_id,
    jsonb_build_object('reason', p_reason));

  RETURN v_req_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_account_deletion(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_account_deletion(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 5: export_user_data RPC (PRIV-05)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.export_user_data()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_result  jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Login required'; END IF;

  SELECT jsonb_build_object(
    'exported_at', now(),
    'user_id',     v_user_id,
    'profile', (
      SELECT row_to_json(p) FROM public.profiles p WHERE id = v_user_id
    ),
    'vehicles', (
      SELECT jsonb_agg(row_to_json(v)) FROM public.vehicles v WHERE customer_id = v_user_id
    ),
    'repair_jobs', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'status', r.status, 'created_at', r.created_at,
        'scheduled_date', r.scheduled_date, 'final_cost', r.final_cost,
        'service_area', r.service_area
      )) FROM public.repair_jobs r WHERE customer_id = v_user_id
    ),
    'consents', (
      SELECT jsonb_agg(row_to_json(c)) FROM public.consents c WHERE user_id = v_user_id
    ),
    'notifications', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', n.id, 'title', n.title, 'created_at', n.created_at, 'is_read', n.is_read
      )) FROM public.notifications n WHERE user_id = v_user_id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.export_user_data() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.export_user_data() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 6: record_consent RPC (PRIV-06)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.record_consent(p_doc text, p_version text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF p_doc NOT IN ('terms','privacy','estimation') THEN
    RAISE EXCEPTION 'Invalid consent doc: %', p_doc;
  END IF;
  INSERT INTO public.consents (user_id, doc, version)
  VALUES (auth.uid(), p_doc, p_version)
  ON CONFLICT (user_id, doc, version) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_consent(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_consent(text, text) TO authenticated;

-- Verifikasi
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema='public' AND table_name IN ('consents','account_deletion_requests')
-- ORDER BY table_name;
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname IN ('request_account_deletion','export_user_data','record_consent')
-- ORDER BY proname;
