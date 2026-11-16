-- Let an applicant read their own application once they are signed in.
--
-- The application is filed from an anonymous (guest) session, so `submitted_by`
-- is the guest's uid. The account created for the applicant carries the row
-- through `auth_user_id`, and the address they typed is `email`. Until now the
-- only applicant policy was `submitted_by = auth.uid()`, so a candidate who
-- signed in on another device (with the credentials from the welcome email, or
-- a magic link) got an empty list — the application was invisible to them.
--
-- The address is the applicant's own login identity, and it is verified by the
-- OTP before the flags are set, so matching on it is the same trust the rest
-- of the flow already assumes. Guest sessions have auth.email() = null, so the
-- guest path still matches on `submitted_by` alone.

drop policy if exists "applicant can read own application" on public.partner_applications;

create policy "applicant can read own application"
  on public.partner_applications
  for select
  using (
    submitted_by = auth.uid()
    or auth_user_id = auth.uid()
    or (email is not null and lower(email) = lower(coalesce(auth.email(), '')))
  );
