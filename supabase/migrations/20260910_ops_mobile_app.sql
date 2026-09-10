-- Migration: Ops Mobile App Support
-- Adds new roles to profiles and creates job_milestones table.

-- 1. Update profiles role constraint
-- We use a DO block to dynamically drop the existing role check constraint 
-- since its name might vary or be auto-generated (e.g., profiles_role_check).
DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%role%';

    IF constraint_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || constraint_name;
    END IF;
END $$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check 
  CHECK (role IN ('customer', 'partner_mechanic', 'master_admin', 'partner_staff', 'partner_driver'));


-- 2. Create job_milestones table
CREATE TABLE IF NOT EXISTS public.job_milestones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
    milestone_name TEXT NOT NULL, -- e.g. 'disassembly', 'panel_beating', 'painting', 'qc'
    status TEXT NOT NULL CHECK (status IN ('pending', 'in_progress', 'completed')),
    completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    completed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Create job_milestone_photos table for evidence
CREATE TABLE IF NOT EXISTS public.job_milestone_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    milestone_id UUID NOT NULL REFERENCES public.job_milestones(id) ON DELETE CASCADE,
    uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    file_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Enable RLS
ALTER TABLE public.job_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_milestone_photos ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies
-- Master admin sees all
CREATE POLICY "Enable ALL for master_admin on job_milestones" ON public.job_milestones
    FOR ALL TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Enable ALL for master_admin on job_milestone_photos" ON public.job_milestone_photos
    FOR ALL TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin');

-- Partner personnel (mechanic, staff, driver) see milestones for their jobs
CREATE POLICY "Enable SELECT for partner personnel on job_milestones" ON public.job_milestones
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = job_milestones.job_id
              AND r.partner_id = (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
        )
    );

CREATE POLICY "Enable INSERT/UPDATE for partner personnel on job_milestones" ON public.job_milestones
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = job_milestones.job_id
              AND r.partner_id = (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = job_milestones.job_id
              AND r.partner_id = (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
        )
    );

-- Similar for photos
CREATE POLICY "Enable SELECT for partner personnel on job_milestone_photos" ON public.job_milestone_photos
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.job_milestones m
            JOIN public.repair_jobs r ON m.job_id = r.id
            WHERE m.id = job_milestone_photos.milestone_id
              AND r.partner_id = (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
        )
    );

CREATE POLICY "Enable INSERT for partner personnel on job_milestone_photos" ON public.job_milestone_photos
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.job_milestones m
            JOIN public.repair_jobs r ON m.job_id = r.id
            WHERE m.id = job_milestone_photos.milestone_id
              AND r.partner_id = (SELECT partner_id FROM public.profiles WHERE id = auth.uid())
        )
    );

-- Customer sees their own milestones
CREATE POLICY "Enable SELECT for customers on job_milestones" ON public.job_milestones
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.repair_jobs r
            WHERE r.id = job_milestones.job_id
              AND r.customer_id = auth.uid()
        )
    );

CREATE POLICY "Enable SELECT for customers on job_milestone_photos" ON public.job_milestone_photos
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.job_milestones m
            JOIN public.repair_jobs r ON m.job_id = r.id
            WHERE m.id = job_milestone_photos.milestone_id
              AND r.customer_id = auth.uid()
        )
    );
