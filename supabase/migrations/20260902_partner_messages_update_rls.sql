-- Add UPDATE policies for partner_messages
CREATE POLICY "Master Admins can update partner messages" ON public.partner_messages
    FOR UPDATE TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Partners can update their own messages" ON public.partner_messages
    FOR UPDATE TO authenticated
    USING (
      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'partner_mechanic' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'partner_mechanic') 
      AND (auth.jwt() -> 'user_metadata' ->> 'partner_id')::uuid = partner_id
    );
