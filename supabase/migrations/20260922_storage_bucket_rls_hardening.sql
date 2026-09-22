-- ═══════════════════════════════════════════════════════════════════════════════
-- SEC-05: close the open read/write policies on the 'revive-photos' bucket
--
-- Verified live against project ahaospjkkuetkaixwzzz on 2026-09-22:
--
--   INSERT  "Allow Public Uploads"  roles=public  WITH CHECK (bucket_id='revive-photos')
--     POST /storage/v1/object/revive-photos/anon-probe/hole.jpg with nothing but the
--     anon key  →  200 {"Key":"revive-photos/anon-probe/hole.jpg"}
--     Any path, any bytes, no session. The SEC-04 comment at
--     estimator_screen.dart:143 assumes this insert is scoped to <auth.uid()>/ — it is not.
--
--   SELECT  "Public Read Access"  roles=public  USING (bucket_id='revive-photos')
--     GET /storage/v1/object/revive-photos/proof_37e9d9fe-....pdf  →  200, 14318 bytes,
--     the customer's whole payment proof. Every damage photo, transfer proof and
--     partner KTP/NIB document in the bucket was world-readable through the RLS endpoint.
--
-- Two path families that had NO policy of their own were being carried by those two
-- holes and are granted explicitly here:
--   partners/<partner_id>/docs|facility/...   partner_profile_controller.dart:395,465
--   ops/<partner_id>/...                      already covered by the ops policies
--
-- The intended scopes keep working:
--   <auth.uid()>/...  own-folder INSERT/SELECT/DELETE policies (guest estimator,
--                     registration, transfer proofs, partner progress photos).
--                     GuestSession.ensure() signs the visitor in anonymously, which
--                     yields a real `authenticated` JWT, so these still pass.
--   ops/<partner_id>/...  ops-role policies (unchanged)
--   admins                is_master_admin() policies (unchanged)
--
-- Idempotent: the two DROP POLICY statements are safe re-runs.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Remove the two world-open policies ───────────────────────────────────
DROP POLICY IF EXISTS "Allow Public Uploads" ON storage.objects;
DROP POLICY IF EXISTS "Public Read Access"   ON storage.objects;

-- ─── 2. WRITE: partner members upload into their own partner folder ──────────
-- Identity comes from the same two sources the application itself trusts:
--   * auth.jwt() -> app_metadata -> 'partner_id'  (this is exactly what
--     public.get_my_partner_id() returns, and what set_user_role() writes)
--   * public.memberships  scope='partner', status='active', role in (owner, mechanic, staff)
-- partners.user_id is deliberately NOT used: it is NULL on every row in this project.
DROP POLICY IF EXISTS "Partner members can upload to their partner folder" ON storage.objects;
CREATE POLICY "Partner members can upload to their partner folder"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'partners'
    AND (
      (
        (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
    )
  );

-- ─── 3. READ: partner members read their own partner folder ──────────────────
DROP POLICY IF EXISTS "Partner members can read their partner folder" ON storage.objects;
CREATE POLICY "Partner members can read their partner folder"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = 'partners'
    AND (
      (
        (auth.jwt() -> 'app_metadata' ->> 'partner_id') IS NOT NULL
        AND (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid
            = ((storage.foldername(name))[2])::uuid
      )
      OR public.has_partner_membership(
           ((storage.foldername(name))[2])::uuid,
           ARRAY['owner', 'mechanic', 'staff']::membership_role[]
         )
    )
  );

-- ─── 4. READ: job participants read photos attached to their own job ─────────
-- Replaces what "Public Read Access" was accidentally providing: the customer
-- tracking gallery (job_stream_controller.dart) and the partner job thumbnails
-- (partner_dashboard_controller.dart:198). Scope the readable set to keys that
-- are actually recorded against a job the caller is party to, so a signed-in
-- user cannot enumerate the bucket.
DROP POLICY IF EXISTS "Job participants can read job photos" ON storage.objects;
CREATE POLICY "Job participants can read job photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (
      EXISTS (
        SELECT 1
          FROM public.repair_photos rp
          JOIN public.repair_jobs   rj ON rj.id = rp.job_id
         WHERE rp.r2_file_key = storage.objects.name
           AND (
             rj.customer_id = auth.uid()
             OR public.has_partner_membership(
                  rj.partner_id,
                  ARRAY['owner', 'mechanic', 'staff']::membership_role[]
                )
           )
      )
      OR EXISTS (
        SELECT 1
          FROM public.job_milestone_photos jmp
          JOIN public.repair_jobs         rj ON rj.id = jmp.job_id
         WHERE jmp.file_key = storage.objects.name
           AND (
             rj.customer_id = auth.uid()
             OR public.has_partner_membership(
                  rj.partner_id,
                  ARRAY['owner', 'mechanic', 'staff']::membership_role[]
                )
           )
      )
    )
  );

-- ─── 5. Net effect on storage.objects for this bucket ────────────────────────
--   SELECT  Users can read own files            authenticated   <uid>/...
--   SELECT  Admins can read all files           is_master_admin()
--   SELECT  Ops roles can read milestone photos partner_staff|partner_driver   ops/...
--   SELECT  Partner members can read ...        (new, §3)
--   SELECT  Job participants can read ...       (new, §4)
--   INSERT  Users can upload to own folder      authenticated   <uid>/...
--   INSERT  Ops roles can upload milestone ...  partner_staff|partner_driver   ops/...
--   INSERT  Partner members can upload ...      (new, §2)
--   DELETE  Users can delete own files          authenticated   <uid>/...
--   REMOVED Allow Public Uploads, Public Read Access
--
-- service_role bypasses RLS and is unaffected.
-- Legacy root-level objects stay readable to the job's own customer/partner via
-- the key match in §4, and to admins via §5. Unreferenced root-level CMS assets
-- become admin-only.
