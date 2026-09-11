-- Migration: Add RLS for partner personnel on repair_photos

CREATE POLICY "Enable SELECT for partner personnel on repair_photos" ON public.repair_photos
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = repair_photos.job_id 
            AND r.partner_id = COALESCE(auth.jwt() -> 'app_metadata' ->> 'partner_id', auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid
        )
    );

CREATE POLICY "Enable INSERT for partner personnel on repair_photos" ON public.repair_photos
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = repair_photos.job_id 
            AND r.partner_id = COALESCE(auth.jwt() -> 'app_metadata' ->> 'partner_id', auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid
        )
    );
