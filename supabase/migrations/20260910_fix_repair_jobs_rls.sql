-- Migration: Fix RLS for partner personnel on repair_jobs to check both metadata locations

DROP POLICY IF EXISTS "Enable SELECT for partner personnel on repair_jobs" ON public.repair_jobs;
CREATE POLICY "Enable SELECT for partner personnel on repair_jobs" ON public.repair_jobs
    FOR SELECT USING (
        partner_id = COALESCE(auth.jwt() -> 'app_metadata' ->> 'partner_id', auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid
    );

DROP POLICY IF EXISTS "Enable UPDATE for partner personnel on repair_jobs" ON public.repair_jobs;
CREATE POLICY "Enable UPDATE for partner personnel on repair_jobs" ON public.repair_jobs
    FOR UPDATE USING (
        partner_id = COALESCE(auth.jwt() -> 'app_metadata' ->> 'partner_id', auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid
    );
