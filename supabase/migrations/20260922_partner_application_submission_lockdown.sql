-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-06: partner applications may only be created through the edge function
--
-- Live policy before this migration (verified 2026-09-22):
--
--   'Enable insert for anyone'  INSERT  roles={public}  WITH CHECK (true)
--
-- An unrestricted INSERT for the `public` role. GuestSession.ensure() mints an
-- anonymous session on demand, so the endpoint was effectively open: anyone
-- holding the anon key could script rows straight into the admin Partner
-- Assessment queue, with no validation, no attribution and no evidence.
--
-- The only legitimate writer is now the `submit-partner-application` edge
-- function, which runs as service_role (bypasses RLS) and validates:
--   * required fields present, email well formed
--   * every *_file_key / facility_photo_keys[].file_key sits under the caller's
--     own '<uid>/partner-applications/' prefix — no citing someone else's objects
--   * at least one photo or legal document attached
--   * max 3 submissions per session per rolling 24h
--   * one pending application per email
--
-- After this migration there is NO insert policy for anon/authenticated on this
-- table, so a direct PostgREST insert is refused by RLS.
--
-- Client side: partner_registration_screen.dart must call the function instead of
-- .from('partner_applications').insert(...) — applied in the same change.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Attribute each application to the session that filed it ──────────────
-- Needed for the per-session rate limit; also gives the reviewer a record of who
-- submitted, which the old unrestricted insert could not provide.
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS submitted_by UUID;

COMMENT ON COLUMN public.partner_applications.submitted_by IS
  'auth.uid() of the submitting session (may be an anonymous guest). Written by submit-partner-application.';

CREATE INDEX IF NOT EXISTS idx_partner_applications_submitted_by_created
  ON public.partner_applications(submitted_by, created_at DESC);

-- ─── 2. One pending application per email ────────────────────────────────────
-- Backstop for the function's own check, so a race cannot leave the reviewer with
-- two live rows for the same workshop. Partial: rejected/approved history is
-- unaffected, so a workshop may re-apply after a rejection.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_partner_applications_pending_email
  ON public.partner_applications (lower(email))
  WHERE status = 'pending';

-- ─── 3. Close the open insert ────────────────────────────────────────────────
DROP POLICY IF EXISTS "Enable insert for anyone" ON public.partner_applications;

-- Deliberately no replacement INSERT policy: service_role bypasses RLS, and
-- service_role is reachable only from the edge function. Reads and updates stay
-- master_admin-only as before ('Enable read for master_admin',
-- 'Enable update for master_admin').
