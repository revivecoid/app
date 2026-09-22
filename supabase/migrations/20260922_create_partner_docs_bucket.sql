-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-08: make 'partner-docs' real, or stop referencing it
--
-- 20260920_memberships_foundation.sql defines storage RLS policies that reference
-- a 'partner-docs' bucket, but the bucket was never created. The Storage API
-- answered {"error":"Bucket not found","code":"NoSuchBucket"} for every request
-- against it, which is why an earlier probe of that bucket returned
-- 'Bucket not found' rather than a policy denial.
--
-- Nothing is broken today: `partner-docs` appears in 0 Dart files, and
-- partner_profile_controller.dart routes NIB/NPWP/SIUP/KTP through 'revive-photos'
-- (static const _bucket = 'revive-photos'). The migration records were simply
-- describing a store that did not exist.
--
-- This creates it as the private, owner-scoped store those migrations describe, so
-- the documented layout is real and future code can rely on it. It is NOT
-- retrofitted as the destination for existing documents — those live in
-- 'revive-photos' and moving them would break the app.
--
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('partner-docs', 'partner-docs', false, 10485760)
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = COALESCE(storage.buckets.file_size_limit, 10485760);

-- Owner-scoped access, matching the intent of 20260920_memberships_foundation.
-- Path layout mirrors the convention used in 'revive-photos':
--   partners/<partner_id>/docs/<type>_<ts>.<ext>
-- Identity comes from the JWT claim app_metadata.partner_id (what
-- get_my_partner_id() returns and set_user_role() writes) or an active partner
-- membership — partners.user_id is NULL on every row, so it is not used.
DROP POLICY IF EXISTS "Partner members manage their docs" ON storage.objects;
CREATE POLICY "Partner members manage their docs"
  ON storage.objects
  FOR ALL
  TO authenticated
  USING (
    bucket_id = 'partner-docs'
    AND (
      (
        (storage.foldername(name))[1] = 'partners'
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
      OR public.is_master_admin()
    )
  )
  WITH CHECK (
    bucket_id = 'partner-docs'
    AND (
      (
        (storage.foldername(name))[1] = 'partners'
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
      OR public.is_master_admin()
    )
  );
