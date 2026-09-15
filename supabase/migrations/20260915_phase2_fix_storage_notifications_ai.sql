-- ═══════════════════════════════════════════════════════════════════════════════
-- PHASE 2 REMEDIATION: Storage, Notifications, AI Config, Booking Slots
-- Fixes: SEC-04, SEC-17, SEC-18, REL-03, DAT-07
-- Audit: revive.co.id code review · 10 September 2026
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- SEC-04: Storage access policies for 'revive-photos' bucket
-- NOTE: The bucket itself must be toggled to "private" via:
--       Supabase Dashboard → Storage → revive-photos → Edit → uncheck "Public"
--
-- Supabase storage policies are RLS policies on storage.objects, NOT rows
-- in storage.policies. The correct approach is CREATE POLICY ON storage.objects.
-- ─────────────────────────────────────────────────────────────────────────────

-- Allow authenticated users to upload to their own folder: <user_id>/<filename>
DROP POLICY IF EXISTS "Users can upload to own folder" ON storage.objects;
CREATE POLICY "Users can upload to own folder"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow users to read their own files (needed for signed URL generation)
DROP POLICY IF EXISTS "Users can read own files" ON storage.objects;
CREATE POLICY "Users can read own files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow users to delete their own files
DROP POLICY IF EXISTS "Users can delete own files" ON storage.objects;
CREATE POLICY "Users can delete own files"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow admins to read all files (for job review in admin dashboard)
DROP POLICY IF EXISTS "Admins can read all files" ON storage.objects;
CREATE POLICY "Admins can read all files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'revive-photos'
    AND public.is_master_admin()
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- REL-03: Add missing is_read column and UPDATE/DELETE policies for notifications
-- ─────────────────────────────────────────────────────────────────────────────

-- Add is_read column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'is_read'
  ) THEN
    ALTER TABLE public.notifications ADD COLUMN is_read BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Allow users to update their own notifications (mark as read)
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own notifications
DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
CREATE POLICY "Users can delete own notifications"
ON public.notifications FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- Allow service role to insert notifications (from send-notification Edge Function)
DROP POLICY IF EXISTS "Service can insert notifications" ON public.notifications;
CREATE POLICY "Service can insert notifications"
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (true);  -- Edge Function uses service_role which bypasses RLS


-- ─────────────────────────────────────────────────────────────────────────────
-- SEC-17: Tighten partner_booked_slots INSERT policy
-- Old policy: any authenticated user can insert any slot
-- New policy: only the owner of the related job can insert a booking slot
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Authenticated users can insert booked slots" ON public.partner_booked_slots;
CREATE POLICY "Job owner can insert booked slots" ON public.partner_booked_slots
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.repair_jobs
    WHERE repair_jobs.id = partner_booked_slots.job_id
      AND repair_jobs.customer_id = auth.uid()
  )
  OR public.is_master_admin()
);


-- ─────────────────────────────────────────────────────────────────────────────
-- SEC-18: Restrict ai_config to admin-only (service role bypasses RLS anyway)
-- The vision-estimation Edge Function uses service_role_key, so no client read needed
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Authenticated users can read ai_config" ON public.ai_config;


-- ─────────────────────────────────────────────────────────────────────────────
-- DAT-07: Fix WhatsApp default mismatch between DB (true) and Dart (false)
-- Server had DEFAULT true → users could receive WhatsApp without opt-in
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.notification_preferences 
  ALTER COLUMN whatsapp SET DEFAULT false;
