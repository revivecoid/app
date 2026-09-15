-- ═══════════════════════════════════════════════════════════════════════════════
-- PHASE 4 REMEDIATION: Schema Reconciliation & Data Integrity
-- Fixes: DAT-01, DAT-02, DAT-03, DAT-08, DAT-09
-- 
-- SAFE STRATEGY: All additions use ADD COLUMN IF NOT EXISTS.
-- Idempotent: safe to run whether production has the columns or not.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-01/02: Add missing columns to repair_jobs
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.repair_jobs
  ADD COLUMN IF NOT EXISTS service_area         TEXT,
  ADD COLUMN IF NOT EXISTS final_price          NUMERIC,
  ADD COLUMN IF NOT EXISTS completed_at         TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS status_changed_at    TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS updated_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_repair_jobs_updated_at ON public.repair_jobs;
CREATE TRIGGER set_repair_jobs_updated_at
  BEFORE UPDATE ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Auto-capture status_changed_at when status column changes
CREATE OR REPLACE FUNCTION public.capture_status_changed_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.status_changed_at = NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_repair_jobs_status_change_capture ON public.repair_jobs;
CREATE TRIGGER on_repair_jobs_status_change_capture
  BEFORE UPDATE OF status ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.capture_status_changed_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-01/02: Add missing columns to vehicles
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS color               TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_type        TEXT,
  ADD COLUMN IF NOT EXISTS vin                 TEXT,
  ADD COLUMN IF NOT EXISTS insurance_provider  TEXT,
  ADD COLUMN IF NOT EXISTS is_insured          BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW();

DROP TRIGGER IF EXISTS set_vehicles_updated_at ON public.vehicles;
CREATE TRIGGER set_vehicles_updated_at
  BEFORE UPDATE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-01/03: Add missing / renamed columns to partners
-- The Dart code references: entity_name, paint_brand, throughput_capacity,
-- service_radius_km, workshop_name, contact_email, user_id
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS entity_name          TEXT,
  ADD COLUMN IF NOT EXISTS paint_brand          TEXT,
  ADD COLUMN IF NOT EXISTS throughput_capacity  INTEGER DEFAULT 3,
  ADD COLUMN IF NOT EXISTS service_radius_km    INTEGER DEFAULT 25,
  ADD COLUMN IF NOT EXISTS workshop_name        TEXT,
  ADD COLUMN IF NOT EXISTS contact_email        TEXT,
  ADD COLUMN IF NOT EXISTS user_id              UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS service_area         TEXT,
  ADD COLUMN IF NOT EXISTS updated_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- DAT-03: Populate entity_name from shop_name for existing rows (reconcile naming)
UPDATE public.partners
  SET entity_name = shop_name
  WHERE entity_name IS NULL AND shop_name IS NOT NULL;

DROP TRIGGER IF EXISTS set_partners_updated_at ON public.partners;
CREATE TRIGGER set_partners_updated_at
  BEFORE UPDATE ON public.partners
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-01/02: Add missing columns to notification_preferences
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

DROP TRIGGER IF EXISTS set_notif_prefs_updated_at ON public.notification_preferences;
CREATE TRIGGER set_notif_prefs_updated_at
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-08: Unique constraint on vehicles to prevent duplicate registrations
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'vehicles'
      AND constraint_name = 'vehicles_customer_license_unique'
  ) THEN
    ALTER TABLE public.vehicles
      ADD CONSTRAINT vehicles_customer_license_unique
      UNIQUE (customer_id, license_plate);
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-09: Performance indexes on frequently filtered columns
-- ─────────────────────────────────────────────────────────────────────────────

-- repair_jobs — most frequently queried columns
CREATE INDEX IF NOT EXISTS idx_repair_jobs_customer_id    ON public.repair_jobs(customer_id);
CREATE INDEX IF NOT EXISTS idx_repair_jobs_partner_id     ON public.repair_jobs(partner_id);
CREATE INDEX IF NOT EXISTS idx_repair_jobs_status         ON public.repair_jobs(status);
CREATE INDEX IF NOT EXISTS idx_repair_jobs_scheduled_date ON public.repair_jobs(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_repair_jobs_created_at     ON public.repair_jobs(created_at DESC);

-- repair_photos — streamed by job_id
CREATE INDEX IF NOT EXISTS idx_repair_photos_job_id       ON public.repair_photos(job_id);
CREATE INDEX IF NOT EXISTS idx_repair_photos_uploaded_at  ON public.repair_photos(uploaded_at DESC);

-- vehicles — customer lookup
CREATE INDEX IF NOT EXISTS idx_vehicles_customer_id       ON public.vehicles(customer_id);

-- partner_messages — unread count query
CREATE INDEX IF NOT EXISTS idx_partner_messages_partner_id ON public.partner_messages(partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_messages_is_read    ON public.partner_messages(is_read);

-- notifications — user feed query
CREATE INDEX IF NOT EXISTS idx_notifications_user_id      ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read      ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at   ON public.notifications(created_at DESC);
