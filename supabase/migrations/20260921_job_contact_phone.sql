-- =============================================================================
-- Per-job customer contact number
-- Date: 2026-09-21
--
-- Why
-- ---
-- The estimator's contact step collects a WhatsApp number, shows it back to the
-- customer on the review screen, and then never writes it anywhere. It lives
-- only in SharedPreferences (browser localStorage) via customer_intake_provider,
-- so it is lost the moment the customer uses another device or clears storage.
-- The job rows carried no contact column at all, and profiles.phone was NULL on
-- every account — 0 of 11 — because the only writer is the profile edit sheet,
-- which the booking flow never opens.
--
-- The workshop therefore had no way to phone the customer about a pickup, and
-- the ops logistics card rendered "No phone provided".
--
-- This adds a per-job snapshot: the number the customer confirmed for THIS
-- booking. It deliberately does not replace profiles.phone — the client writes
-- that too, as the canonical person record — because a job should keep the
-- number it was booked with even if the profile number changes later.
--
-- ops_view_mode-style client-side note: this column is read by the valet screen
-- and falls back to profiles.phone, then profiles.email. RLS on repair_jobs
-- already scopes reads by partner_id, so the existing policies cover it and no
-- new policy is needed.
-- =============================================================================

ALTER TABLE public.repair_jobs
  ADD COLUMN IF NOT EXISTS contact_phone text;

COMMENT ON COLUMN public.repair_jobs.contact_phone IS
  'Customer contact number captured at booking, snapshotted onto the job so the '
  'workshop can reach whoever booked it even if profiles.phone later changes. '
  'Written by the estimator booking flow; read by the ops valet screen.';

-- Existing jobs predate this column, so backfill from the profile where a number
-- exists, rather than leaving the valet screen blank for jobs already in flight.
-- Currently a no-op (profiles.phone is unset everywhere) but correct if any
-- account has since added one.
UPDATE public.repair_jobs r
   SET contact_phone = NULLIF(p.phone, '')
  FROM public.profiles p
 WHERE p.id = r.customer_id
   AND r.contact_phone IS NULL
   AND NULLIF(p.phone, '') IS NOT NULL;

-- Single trailing SELECT: the Management API returns only the last result set.
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'repair_jobs'
      AND column_name = 'contact_phone')                        AS has_contact_phone,
  (SELECT count(*) FROM public.repair_jobs
    WHERE contact_phone IS NOT NULL AND contact_phone <> '')     AS jobs_with_number;
