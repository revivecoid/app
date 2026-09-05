-- Enable Master Admin to read everything for CRM purposes
CREATE POLICY "Master Admins can read all profiles" ON public.profiles
    FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Master Admins can read all partners" ON public.partners
    FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Master Admins can update all partners" ON public.partners
    FOR UPDATE TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin')
    WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

CREATE POLICY "Master Admins can delete all partners" ON public.partners
    FOR DELETE TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'master_admin' OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'master_admin');

