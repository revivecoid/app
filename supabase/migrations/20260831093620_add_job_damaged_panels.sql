-- 1. Create a definitive database enum for exact car panel types
CREATE TYPE public.car_panel AS ENUM (
    'bumper_depan', 'spoiler_bumper_depan', 'kap_mesin',
    'bumper_belakang', 'spoiler_bumper_belakang', 'bagasi', 'spoiler_bagasi',
    'fender_rh', 'pintu_depan_rh', 'spion_rh', 'pintu_belakang_rh', 'quarter_rh', 'trisplang_rh', 'side_roof_rh',
    'fender_lh', 'pintu_depan_lh', 'spion_lh', 'pintu_belakang_lh', 'quarter_lh', 'trisplang_lh', 'side_roof_lh',
    'roof', 'cover'
);

-- 2. Transactional sub-ledger tracking multiple damage tags per repair job
CREATE TABLE public.job_damaged_panels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
    panel_name public.car_panel NOT NULL,
    customer_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(job_id, panel_name)
);

-- 3. Bind Role-Based Row-Level Security (RLS)
ALTER TABLE public.job_damaged_panels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Customers can manage damaged panels for their own jobs" 
ON public.job_damaged_panels FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.repair_jobs 
        WHERE public.repair_jobs.id = job_id 
        AND public.repair_jobs.customer_id = auth.uid()
    )
);
