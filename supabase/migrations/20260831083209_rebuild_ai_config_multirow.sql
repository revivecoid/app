-- CORRECTIVE MIGRATION: Rebuild ai_config as multi-row model registry
-- per System Design Specification Section 3.
-- The original migration incorrectly used a single-row (id=1) design.

-- Step 1: Drop the incorrect single-row table
DROP TABLE IF EXISTS public.ai_config CASCADE;

-- Step 2: Recreate as proper multi-row model registry
CREATE TABLE public.ai_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_name TEXT UNIQUE NOT NULL,
    provider TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT false,
    priority_order INTEGER NOT NULL DEFAULT 99,
    api_base_url TEXT NOT NULL,
    payload_format TEXT NOT NULL CHECK (payload_format IN ('gemini', 'openai', 'groq')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 3: Seed the 3 configured AI vision model endpoints
INSERT INTO public.ai_config (model_name, provider, is_active, priority_order, api_base_url, payload_format)
VALUES
    -- Priority 1: Google Gemini 2.5 Flash (Active primary — free tier)
    (
        'gemini-2.5-flash',
        'Google Gemini',
        true,
        1,
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
        'gemini'
    ),
    -- Priority 2: Groq Llama 3.2 Vision (Fallback — free tier, ultra-fast inference)
    (
        'llama-3.2-11b-vision-preview',
        'Groq',
        false,
        2,
        'https://api.groq.com/openai/v1/chat/completions',
        'openai'
    ),
    -- Priority 3: OpenAI GPT-4o (Secondary fallback — premium tier)
    (
        'gpt-4o',
        'OpenAI',
        false,
        3,
        'https://api.openai.com/v1/chat/completions',
        'openai'
    );

-- Step 4: Re-enable RLS
ALTER TABLE public.ai_config ENABLE ROW LEVEL SECURITY;

-- Step 5: Master admin full access policy
CREATE POLICY "Master admin can manage ai_config"
    ON public.ai_config
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role = 'master_admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role = 'master_admin'
        )
    );

-- Step 6: All authenticated users can SELECT (needed by the estimator serverless function)
CREATE POLICY "Authenticated users can read ai_config"
    ON public.ai_config
    FOR SELECT
    TO authenticated
    USING (true);
