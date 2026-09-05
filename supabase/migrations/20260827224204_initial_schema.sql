-- Create extension for UUID generation if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. partners table
CREATE TABLE IF NOT EXISTS public.partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_name TEXT NOT NULL,
    email TEXT,
    address TEXT,
    phone TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    role TEXT CHECK (role IN ('customer', 'partner_mechanic', 'master_admin')) NOT NULL,
    partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. vehicles table
CREATE TABLE IF NOT EXISTS public.vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    make TEXT NOT NULL,
    model TEXT NOT NULL,
    year INTEGER NOT NULL,
    license_plate TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. repair_jobs table
CREATE TABLE IF NOT EXISTS public.repair_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
    initial_estimation_cost NUMERIC,
    final_cost NUMERIC,
    status TEXT CHECK (status IN (
        '1_intake',
        '2_estimated',
        '3_booked',
        '4_paid',
        '5_admitted',
        '6_in_progress',
        '7_finished',
        '8_awaiting_delivery',
        '9_done'
    )) NOT NULL,
    delivery_type TEXT CHECK (delivery_type IN ('self_deliver', 'pickup')),
    scheduled_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. repair_photos table
CREATE TABLE IF NOT EXISTS public.repair_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
    step_context TEXT CHECK (step_context IN ('intake', 'progress', 'finished')) NOT NULL,
    r2_file_key TEXT NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. ai_config table
CREATE TABLE IF NOT EXISTS public.ai_config (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Single row configuration
    primary_model_provider TEXT NOT NULL DEFAULT 'google',
    primary_model_name TEXT NOT NULL DEFAULT 'gemini-2.5-flash',
    fallback_model_provider TEXT,
    fallback_model_name TEXT,
    system_instruction_context TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default AI config row
INSERT INTO public.ai_config (id, primary_model_provider, primary_model_name, fallback_model_provider, fallback_model_name, system_instruction_context)
VALUES (1, 'google', 'gemini-2.5-flash', 'groq', 'llama-3.2-11b-vision-preview', 'You are an automotive body repair estimator...')
ON CONFLICT (id) DO NOTHING;

-- 7. ai_training_context table
CREATE TABLE IF NOT EXISTS public.ai_training_context (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    car_make_model TEXT NOT NULL,
    damage_description TEXT NOT NULL,
    resolved_actual_cost NUMERIC NOT NULL,
    is_active_context BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Basic RLS Policies Setup

-- Enable RLS
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.repair_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.repair_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_training_context ENABLE ROW LEVEL SECURITY;
