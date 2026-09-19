-- =============================================================================
-- Migration: Allow partners to read vehicles linked to their assigned jobs
-- Date: 2026-09-19
-- Problem: vehicles table has RLS policies only for owner + admin.
--   Partner staff querying repair_jobs with a vehicle join get NULL for
--   all vehicle fields because RLS blocks the read. This causes the
--   partner kanban to show "Unknown Unknown" / "NO PLATE" even when
--   vehicle data exists.
-- =============================================================================

DROP POLICY IF EXISTS "Partners can read vehicles for assigned jobs" ON public.vehicles;
CREATE POLICY "Partners can read vehicles for assigned jobs" ON public.vehicles
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.repair_jobs rj
            WHERE rj.vehicle_id = vehicles.id
              AND rj.partner_id = (
                  SELECT p.id FROM public.partners p
                  WHERE p.id = (auth.jwt()->'app_metadata'->>'partner_id')::uuid
              )
        )
    );
