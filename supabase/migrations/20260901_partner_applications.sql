CREATE TABLE IF NOT EXISTS public.partner_applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_name TEXT NOT NULL,
    owner_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    address TEXT NOT NULL,
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected')) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.partner_applications ENABLE ROW LEVEL SECURITY;

-- Anyone can insert a new application
CREATE POLICY "Enable insert for anyone" ON public.partner_applications
    FOR INSERT 
    WITH CHECK (true);

-- Only master_admin can view and update
CREATE POLICY "Enable read for master_admin" ON public.partner_applications
    FOR SELECT
    TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Enable update for master_admin" ON public.partner_applications
    FOR UPDATE
    TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin')
    WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');
