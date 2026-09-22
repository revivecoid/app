-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX: submitted workshop applications never reached the database
--
-- Root cause: partner_registration_screen.dart inserts entity_name, tier,
-- paint_brand, throughput_capacity, service_radius_km, submitted_at and the
-- *_file_key columns into public.partner_applications. Those columns were added
-- to `partners` (20260910_expand_partners_table / 20260915_phase4) but never to
-- `partner_applications`, so PostgREST rejected every insert:
--     400 PGRST204 "Could not find the 'entity_name' column of
--                   'partner_applications' in the schema cache"
-- The client swallowed that error and still showed the success screen, so no
-- application row was ever written and nothing appeared in Partner Assessment.
--
-- The original CHECK also rejected the 'pending_review' status the shipped client
-- sent, which would have failed the insert even with the columns present.
--
-- Additive and idempotent — safe to run against live data.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Form fields the client sends but the table never had ──────────────────
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS entity_name         TEXT,
  ADD COLUMN IF NOT EXISTS tier                INTEGER DEFAULT 2,
  ADD COLUMN IF NOT EXISTS paint_brand         TEXT    DEFAULT 'glasurit',
  ADD COLUMN IF NOT EXISTS throughput_capacity INTEGER DEFAULT 12,
  ADD COLUMN IF NOT EXISTS service_radius_km   NUMERIC DEFAULT 15,
  ADD COLUMN IF NOT EXISTS submitted_at        TIMESTAMPTZ DEFAULT NOW();

-- ─── 2. Uploaded evidence ────────────────────────────────────────────────────
-- Storage paths inside the private 'revive-photos' bucket. Mirrors the column
-- names on `partners` so approve-partner can carry them straight across.
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS nib_file_key         TEXT,
  ADD COLUMN IF NOT EXISTS npwp_file_key        TEXT,
  ADD COLUMN IF NOT EXISTS siup_file_key        TEXT,
  ADD COLUMN IF NOT EXISTS ktp_file_key         TEXT,
  -- Facility photos are 4 fixed slots; a JSONB array of
  -- {"slot":0,"label":"Workshop Facade","file_key":"<uid>/partner-applications/..."}
  ADD COLUMN IF NOT EXISTS facility_photo_keys  JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.partner_applications.tier IS
  '1=Flagship Spray Facility, 2=Authorized Partner, 3=Express PDR Center';
COMMENT ON COLUMN public.partner_applications.submitted_at IS
  'Client submit timestamp; backfilled from created_at for legacy rows';
COMMENT ON COLUMN public.partner_applications.facility_photo_keys IS
  'Array of {slot,label,file_key} for the 4 facility photo slots';

-- Legacy rows only ever had created_at.
UPDATE public.partner_applications
   SET submitted_at = created_at
 WHERE submitted_at IS NULL;

-- ─── 3. Status constraint ────────────────────────────────────────────────────
-- Accept the shipped client's 'pending_review', then normalise it to the
-- canonical queue status the admin Partner Assessment filters on.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT con.conname
      FROM pg_constraint con
      JOIN pg_class     rel ON rel.oid = con.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
     WHERE nsp.nspname = 'public'
       AND rel.relname = 'partner_applications'
       AND con.contype = 'c'
       AND pg_get_constraintdef(con.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.partner_applications DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_status_check
  CHECK (status IN ('pending', 'pending_review', 'approved', 'rejected'));

UPDATE public.partner_applications
   SET status = 'pending'
 WHERE status = 'pending_review';

-- ─── 4. Admin queue index ────────────────────────────────────────────────────
-- SELECT ... WHERE status = 'pending' ORDER BY submitted_at DESC
CREATE INDEX IF NOT EXISTS idx_partner_applications_status_submitted
  ON public.partner_applications(status, submitted_at DESC);
