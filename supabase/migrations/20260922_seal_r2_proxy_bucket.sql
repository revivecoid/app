-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-07: seal the legacy 'revive-photos-r2-proxy' bucket
--
-- State before (verified 2026-09-22):
--   storage.buckets.public = true
--   'Public Access' SELECT roles={public} USING (bucket_id='revive-photos-r2-proxy')
--   'Auth Upload'   INSERT roles={public} WITH CHECK (… AND auth.role()='authenticated')
--   'Auth Update'   UPDATE roles={public} WITH CHECK (… AND auth.role()='authenticated')
--
-- So every object in it was world-readable on the public route, and any signed-in
-- user could write arbitrary paths into it.
--
-- This bucket was created by 20260911_create_storage_bucket.sql and superseded by
-- 'revive-photos'. It holds 4 objects, all dated 2026-09-11. No code in the repo
-- references 'revive-photos-r2-proxy' (0 matches across .dart/.sql/.ts/.json/.toml),
-- so nothing builds URLs against it.
--
-- Data repair carried out alongside this migration:
--   2 of the 4 objects are referenced by public.repair_photos.r2_file_key
--   (uploaded 2026-09-11 07:23–07:26, job 37e9d9fe) and existed ONLY in this
--   bucket. Because the app builds photo URLs against 'revive-photos', those two
--   photos did not resolve at all — a latent broken-image bug. They were copied
--   into 'revive-photos' and verified at 9185 bytes, image/jpeg, before this
--   bucket was made private. The other 2 objects are orphaned (no referencing row).
--
-- Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════════

UPDATE storage.buckets
   SET public = false
 WHERE id = 'revive-photos-r2-proxy';

DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Auth Upload"   ON storage.objects;
DROP POLICY IF EXISTS "Auth Update"   ON storage.objects;

-- Note: the three policies above were named for this bucket, but DROP POLICY
-- matches on the policy name alone. 'revive-photos' has its own separately named
-- policies ('Users can upload to own folder', 'Users can read own files',
-- 'Admins can read all files', …) plus the SEC-05 partner/job policies, so none of
-- those are affected. Verify after applying:
--   select policyname, cmd from pg_policies
--    where schemaname='storage' and tablename='objects'
--      and coalesce(with_check,qual) ilike '%revive-photos-r2-proxy%';
--   -- expected: 0 rows
--
-- After this: the bucket is reachable by service_role only.
