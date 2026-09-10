-- Migration: Add RLS for partner personnel on repair_jobs

CREATE POLICY "Enable SELECT for partner personnel on repair_jobs" ON public.repair_jobs
    FOR SELECT USING (
        partner_id = (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
    );

CREATE POLICY "Enable UPDATE for partner personnel on repair_jobs" ON public.repair_jobs
    FOR UPDATE USING (
        partner_id = (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
    );
