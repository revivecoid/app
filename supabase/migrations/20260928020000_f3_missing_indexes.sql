-- =============================================================================
-- 20260928020000_f3_missing_indexes.sql
-- Fase 3: index yang hilang (C-87)
-- Idempoten — semua memakai IF NOT EXISTS.
-- =============================================================================

-- repair_jobs
CREATE INDEX IF NOT EXISTS idx_repair_jobs_vehicle_id
  ON public.repair_jobs(vehicle_id);

CREATE INDEX IF NOT EXISTS idx_repair_jobs_partner_status
  ON public.repair_jobs(partner_id, status)
  WHERE partner_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_repair_jobs_customer_id
  ON public.repair_jobs(customer_id);

CREATE INDEX IF NOT EXISTS idx_repair_jobs_scheduled_date
  ON public.repair_jobs(scheduled_date)
  WHERE scheduled_date IS NOT NULL;

-- profiles
CREATE INDEX IF NOT EXISTS idx_profiles_partner_id
  ON public.profiles(partner_id)
  WHERE partner_id IS NOT NULL;

-- memberships (dipakai oleh is_master_admin, get_my_partner_id, has_partner_membership)
CREATE INDEX IF NOT EXISTS idx_memberships_user_status
  ON public.memberships(user_id, status);

CREATE INDEX IF NOT EXISTS idx_memberships_org_status
  ON public.memberships(org_id, status)
  WHERE org_id IS NOT NULL;

-- partner_booked_slots
CREATE INDEX IF NOT EXISTS idx_partner_booked_slots_job_id
  ON public.partner_booked_slots(job_id);

CREATE INDEX IF NOT EXISTS idx_partner_booked_slots_partner_date
  ON public.partner_booked_slots(partner_id, booked_date);

-- Verify (run after applying):
-- SELECT indexname, tablename FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND indexname LIKE 'idx_%'
-- ORDER BY tablename, indexname;
