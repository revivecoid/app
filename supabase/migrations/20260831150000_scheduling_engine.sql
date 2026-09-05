-- 1. Workshop Standard Operating Profiles
CREATE TABLE IF NOT EXISTS public.partner_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    standard_working_days INTEGER[] NOT NULL DEFAULT '{1,2,3,4,5,6}', -- 1=Monday
    blacklisted_dates DATE[] DEFAULT '{}',
    simultaneous_panel_capacity INTEGER NOT NULL DEFAULT 1,
    guaranteed_slots_per_day INTEGER NOT NULL DEFAULT 2,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(partner_id)
);

-- 2. Base panel baseline matrix per workshop
CREATE TABLE IF NOT EXISTS public.partner_panel_durations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    panel_name TEXT NOT NULL, 
    repair_duration_hours NUMERIC(4, 1) NOT NULL DEFAULT 2.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(partner_id, panel_name)
);

-- 3. The event manager transaction ledger
CREATE TABLE IF NOT EXISTS public.partner_booked_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL, 
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    booked_date DATE NOT NULL,
    estimated_duration_days INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Setup RLS Policies
ALTER TABLE public.partner_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_panel_durations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_booked_slots ENABLE ROW LEVEL SECURITY;

-- Drop old ones just in case
DROP POLICY IF EXISTS "Partners can manage their schedules" ON public.partner_schedules;
DROP POLICY IF EXISTS "Partners can manage panel durations" ON public.partner_panel_durations;
DROP POLICY IF EXISTS "Partners can view their booked slots" ON public.partner_booked_slots;
DROP POLICY IF EXISTS "Anyone can view partner schedules" ON public.partner_schedules;
DROP POLICY IF EXISTS "Anyone can view panel durations" ON public.partner_panel_durations;
DROP POLICY IF EXISTS "Anyone can view booked slots for availability" ON public.partner_booked_slots;
DROP POLICY IF EXISTS "Authenticated users can insert booked slots" ON public.partner_booked_slots;

-- Corrected RLS
CREATE POLICY "Anyone can view partner schedules" ON public.partner_schedules FOR SELECT USING (true);
CREATE POLICY "Partners can manage their schedules" ON public.partner_schedules FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);

CREATE POLICY "Anyone can view panel durations" ON public.partner_panel_durations FOR SELECT USING (true);
CREATE POLICY "Partners can manage panel durations" ON public.partner_panel_durations FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);

CREATE POLICY "Anyone can view booked slots for availability" ON public.partner_booked_slots FOR SELECT USING (true);
CREATE POLICY "Partners can view their booked slots" ON public.partner_booked_slots FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid = partner_id);
CREATE POLICY "Authenticated users can insert booked slots" ON public.partner_booked_slots FOR INSERT WITH CHECK (auth.role() = 'authenticated');
