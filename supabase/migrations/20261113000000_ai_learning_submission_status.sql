-- Track whether a submission was actually reviewed or abandoned.
--
-- saveSubmission() inserts a row as soon as the AI responds, so an abandoned
-- scan and a fully confirmed one were indistinguishable in the admin
-- dashboard — and the accuracy figures counted both. status/completed_at let
-- the dashboard separate real training data from noise.
--
-- Rows that already exist were created before this column, and we cannot tell
-- after the fact which ones were reviewed, so they are marked 'legacy' rather
-- than guessed at.

ALTER TABLE public.ai_learning_submissions
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE public.ai_learning_submissions
  DROP CONSTRAINT IF EXISTS ai_learning_submissions_status_check;
ALTER TABLE public.ai_learning_submissions
  ADD CONSTRAINT ai_learning_submissions_status_check
  CHECK (status IN ('pending', 'completed', 'legacy'));

-- Backfill: existing rows without reviews are 'legacy'. A row counts as
-- completed if it has any panel review recorded.
UPDATE public.ai_learning_submissions s
SET status = CASE
      WHEN EXISTS (
        SELECT 1 FROM public.ai_learning_panel_reviews r
        WHERE r.submission_id = s.id
      ) THEN 'completed'
      ELSE 'legacy'
    END,
    completed_at = CASE
      WHEN EXISTS (
        SELECT 1 FROM public.ai_learning_panel_reviews r
        WHERE r.submission_id = s.id
      ) THEN COALESCE(s.created_at, NOW())
      ELSE NULL
    END
WHERE s.status = 'pending';

CREATE INDEX IF NOT EXISTS idx_ai_learning_submissions_status_created
  ON public.ai_learning_submissions (status, created_at DESC);

COMMENT ON COLUMN public.ai_learning_submissions.status IS
  'pending = AI ran, respondent not yet finished; completed = verdicts saved; legacy = pre-column row';
