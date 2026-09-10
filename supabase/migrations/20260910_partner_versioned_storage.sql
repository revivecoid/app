-- Migration: Versioned document and photo storage tables for partners
-- All uploads are preserved. Nothing is ever overwritten.
-- is_current = true marks the latest version displayed in the dashboard.

-- ─── 1. partner_documents — versioned legal documents ─────────────────────────
CREATE TABLE IF NOT EXISTS public.partner_documents (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id   UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  doc_type     TEXT NOT NULL CHECK (doc_type IN ('nib','npwp','siup','ktp')),
  file_key     TEXT NOT NULL,          -- Supabase storage object path (R2)
  file_name    TEXT NOT NULL,          -- Original filename shown in UI
  file_size    INTEGER,                -- Bytes
  uploaded_by  UUID REFERENCES auth.users(id),
  uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_current   BOOLEAN NOT NULL DEFAULT true
);

-- Only one row per (partner_id, doc_type) should be current at a time.
-- Enforced in application logic (set old is_current=false before insert).
CREATE INDEX idx_partner_docs_partner_type ON public.partner_documents(partner_id, doc_type);
CREATE INDEX idx_partner_docs_current     ON public.partner_documents(partner_id, doc_type, is_current);

-- ─── 2. partner_facility_photos — versioned facility photos ───────────────────
CREATE TABLE IF NOT EXISTS public.partner_facility_photos (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_id   UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  slot         INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 3),
  label        TEXT,                   -- 'Workshop Facade', 'Spray Oven Booth', etc.
  file_key     TEXT NOT NULL,          -- R2 storage path
  uploaded_by  UUID REFERENCES auth.users(id),
  uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_current   BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX idx_partner_photos_slot    ON public.partner_facility_photos(partner_id, slot);
CREATE INDEX idx_partner_photos_current ON public.partner_facility_photos(partner_id, slot, is_current);

-- ─── 3. Add user_id FK to partners (optional admin-created row linkage) ────────
-- partners.id = auth.uid() for self-registered partners (primary pattern).
-- user_id column added for admin-created rows where id differs from auth UID.
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_partners_user_id ON public.partners(user_id);

-- ─── 4. RLS — partner_documents ───────────────────────────────────────────────
ALTER TABLE public.partner_documents ENABLE ROW LEVEL SECURITY;

-- Partners can manage their own documents
CREATE POLICY "partner_docs_own_select" ON public.partner_documents
  FOR SELECT TO authenticated
  USING (partner_id = auth.uid());

CREATE POLICY "partner_docs_own_insert" ON public.partner_documents
  FOR INSERT TO authenticated
  WITH CHECK (partner_id = auth.uid());

CREATE POLICY "partner_docs_own_update" ON public.partner_documents
  FOR UPDATE TO authenticated
  USING (partner_id = auth.uid());

-- Admins can read all documents
CREATE POLICY "partner_docs_admin_all" ON public.partner_documents
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin'
      OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

-- ─── 5. RLS — partner_facility_photos ────────────────────────────────────────
ALTER TABLE public.partner_facility_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partner_photos_own_select" ON public.partner_facility_photos
  FOR SELECT TO authenticated
  USING (partner_id = auth.uid());

CREATE POLICY "partner_photos_own_insert" ON public.partner_facility_photos
  FOR INSERT TO authenticated
  WITH CHECK (partner_id = auth.uid());

CREATE POLICY "partner_photos_own_update" ON public.partner_facility_photos
  FOR UPDATE TO authenticated
  USING (partner_id = auth.uid());

CREATE POLICY "partner_photos_admin_all" ON public.partner_facility_photos
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin'
      OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');
