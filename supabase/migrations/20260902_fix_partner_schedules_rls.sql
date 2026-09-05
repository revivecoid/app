-- Fix RLS for partner_schedules
DROP POLICY IF EXISTS "Partners can manage their schedules" ON public.partner_schedules;
CREATE POLICY "Partners can manage their schedules" ON public.partner_schedules 
    FOR ALL 
    USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);

-- Fix RLS for partner_panel_durations
DROP POLICY IF EXISTS "Partners can manage panel durations" ON public.partner_panel_durations;
CREATE POLICY "Partners can manage panel durations" ON public.partner_panel_durations 
    FOR ALL 
    USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);

-- Fix RLS for partner_booked_slots
DROP POLICY IF EXISTS "Partners can view their booked slots" ON public.partner_booked_slots;
CREATE POLICY "Partners can view their booked slots" ON public.partner_booked_slots 
    FOR ALL 
    USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);
