-- Migration: Expand partners table with all registration form fields
-- Safe ALTER TABLE — all new columns are nullable with defaults, no data loss.

ALTER TABLE public.partners
  -- Workshop identity
  ADD COLUMN IF NOT EXISTS entity_name TEXT,
  ADD COLUMN IF NOT EXISTS owner_name TEXT,
  -- Tier: 1=Flagship (>10 bays), 2=Authorized (5-9 bays), 3=Express PDR (3-5 bays)
  ADD COLUMN IF NOT EXISTS tier INTEGER DEFAULT 2,
  -- Equipment
  ADD COLUMN IF NOT EXISTS paint_brand TEXT DEFAULT 'glasurit',
  ADD COLUMN IF NOT EXISTS throughput_capacity INTEGER DEFAULT 12,
  ADD COLUMN IF NOT EXISTS service_radius_km NUMERIC DEFAULT 15,
  ADD COLUMN IF NOT EXISTS working_bays INTEGER,
  ADD COLUMN IF NOT EXISTS spray_booths INTEGER,
  -- Legal document storage keys (Supabase storage object paths)
  ADD COLUMN IF NOT EXISTS nib_file_key TEXT,
  ADD COLUMN IF NOT EXISTS npwp_file_key TEXT,
  ADD COLUMN IF NOT EXISTS siup_file_key TEXT,
  ADD COLUMN IF NOT EXISTS ktp_file_key TEXT,
  -- Status tracking
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.partners.tier IS '1=Flagship Spray Facility, 2=Authorized Partner, 3=Express PDR Center';
COMMENT ON COLUMN public.partners.nib_file_key IS 'Supabase storage path for NIB document';
COMMENT ON COLUMN public.partners.npwp_file_key IS 'Supabase storage path for NPWP document';
COMMENT ON COLUMN public.partners.siup_file_key IS 'Supabase storage path for SIUP document';
COMMENT ON COLUMN public.partners.ktp_file_key IS 'Supabase storage path for KTP document';
