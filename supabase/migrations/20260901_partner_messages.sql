-- 1. Create partner_messages table
CREATE TABLE IF NOT EXISTS public.partner_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Enable RLS
ALTER TABLE public.partner_messages ENABLE ROW LEVEL SECURITY;

-- 3. Master Admin Policies (Can read and write all messages)
CREATE POLICY "Master Admins can read all partner messages" ON public.partner_messages
    FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Master Admins can insert partner messages" ON public.partner_messages
    FOR INSERT TO authenticated
    WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

-- 4. Partner Policies (Can read and write their own messages)
CREATE POLICY "Partners can read their own messages" ON public.partner_messages
    FOR SELECT TO authenticated
    USING (
      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'partner_mechanic' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'partner_mechanic') 
      AND (auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid = partner_id
    );

CREATE POLICY "Partners can insert their own messages" ON public.partner_messages
    FOR INSERT TO authenticated
    WITH CHECK (
      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'partner_mechanic' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'partner_mechanic') 
      AND (auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid = partner_id
      AND auth.uid() = sender_id
    );

-- 5. Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.partner_messages;
