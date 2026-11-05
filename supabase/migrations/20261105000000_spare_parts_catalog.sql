-- =============================================================================
-- Migration: spare_parts_catalog
-- Purpose  : Spare parts catalog table for estimation module.
--            Prices start NULL — populated later via vendor DB integration.
-- =============================================================================

-- ── 1. Spare parts catalog ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.spare_parts (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  panel_name      TEXT          NOT NULL,          -- matches pricing_rules.panel_name
  part_name       TEXT          NOT NULL,
  part_number     TEXT,                            -- vendor SKU/OEM code (nullable)
  damage_type     TEXT          NOT NULL           -- 'scratch' | 'dent' | 'broken' | 'any'
                  CHECK (damage_type IN ('scratch', 'dent', 'broken', 'any')),
  quantity        INTEGER       NOT NULL DEFAULT 1,
  reason          TEXT          NOT NULL,          -- human-readable usage reason (ID)
  price           NUMERIC(12,2),                   -- NULL = harga belum tersedia
  vendor_id       UUID,                            -- FK to vendors table (future)
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ── 2. Indexes ──────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_spare_parts_panel_name
  ON public.spare_parts (panel_name);

CREATE INDEX IF NOT EXISTS idx_spare_parts_damage_type
  ON public.spare_parts (damage_type);

CREATE INDEX IF NOT EXISTS idx_spare_parts_active
  ON public.spare_parts (is_active)
  WHERE is_active = true;

-- ── 3. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.spare_parts ENABLE ROW LEVEL SECURITY;

-- Public read: estimation screen can read spare parts catalog without auth
CREATE POLICY "spare_parts_public_read"
  ON public.spare_parts FOR SELECT
  USING (is_active = true);

-- Only service role / master_admin can write (via admin panel, not client)
CREATE POLICY "spare_parts_admin_write"
  ON public.spare_parts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'master_admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'master_admin'
    )
  );

-- ── 4. updated_at trigger ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_spare_parts_updated_at ON public.spare_parts;
CREATE TRIGGER trg_spare_parts_updated_at
  BEFORE UPDATE ON public.spare_parts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 5. Seed: common paint/body consumables (price NULL = vendor TBD) ────────
-- These are the inferred fallbacks from spare_parts_estimation.dart.
-- panel_name = 'ANY' means applies to any panel for that damage type.

INSERT INTO public.spare_parts
  (panel_name, part_name, damage_type, quantity, reason)
VALUES
  -- Replacement panels (panel-specific rows added per vendor catalog)
  -- Paint consumables: applies to any panel
  ('ANY', 'Dempul epoxy primer', 'broken', 1, 'Dasar cat setelah penggantian panel'),
  ('ANY', 'Cat warna (basecoat)', 'broken', 1, 'Finishing setelah penggantian panel'),
  ('ANY', 'Clear coat', 'broken', 1, 'Lapisan pelindung akhir'),

  ('ANY', 'Dempul polyester', 'dent', 1, 'Perbaikan penyok — pengisian permukaan'),
  ('ANY', 'Cat warna (basecoat)', 'dent', 1, 'Finishing setelah perbaikan penyok'),
  ('ANY', 'Clear coat', 'dent', 1, 'Lapisan pelindung akhir'),

  ('ANY', 'Cat warna (basecoat)', 'scratch', 1, 'Perbaikan goresan'),
  ('ANY', 'Clear coat', 'scratch', 1, 'Lapisan pelindung akhir'),
  ('ANY', 'Amplas compound', 'scratch', 1, 'Halus permukaan goresan sebelum cat')
ON CONFLICT DO NOTHING;

-- ── 6. Future: vendors table placeholder comment ────────────────────────────
-- When vendor DB integration is ready:
--   CREATE TABLE public.vendors (
--     id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
--     name        TEXT NOT NULL,
--     contact     TEXT,
--     api_endpoint TEXT,
--     is_active   BOOLEAN DEFAULT true,
--     created_at  TIMESTAMPTZ DEFAULT now()
--   );
--   ALTER TABLE public.spare_parts
--     ADD CONSTRAINT fk_spare_parts_vendor
--     FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL;
