-- AI Learning app: respondent accounts, damage submissions, and per-panel / per-part
-- true/false reviews used as training signal for the damage model.
-- NOT APPLIED to live DB yet. Review, then apply.

-- ─── 1. Respondents ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_learning_respondents (
    user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name    TEXT NOT NULL CHECK (char_length(full_name) BETWEEN 1 AND 120),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.ai_learning_respondents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Respondent reads own row" ON public.ai_learning_respondents;
CREATE POLICY "Respondent reads own row" ON public.ai_learning_respondents
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_master_admin());

DROP POLICY IF EXISTS "Respondent inserts own row" ON public.ai_learning_respondents;
CREATE POLICY "Respondent inserts own row" ON public.ai_learning_respondents
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ─── 2. Submissions (one per scan) ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_learning_submissions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    respondent_id   UUID NOT NULL REFERENCES public.ai_learning_respondents(user_id) ON DELETE CASCADE,
    photo_paths     TEXT[] NOT NULL,            -- storage paths under <uid>/learning/
    selected_panels TEXT[] NOT NULL DEFAULT '{}',
    ai_result       JSONB NOT NULL,             -- raw structuredData from vision-estimation
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_learning_submissions_respondent
  ON public.ai_learning_submissions (respondent_id, created_at DESC);

ALTER TABLE public.ai_learning_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Respondent manages own submissions" ON public.ai_learning_submissions;
CREATE POLICY "Respondent manages own submissions" ON public.ai_learning_submissions
  FOR ALL TO authenticated
  USING (respondent_id = auth.uid())
  WITH CHECK (respondent_id = auth.uid());

DROP POLICY IF EXISTS "Admin reads all submissions" ON public.ai_learning_submissions;
CREATE POLICY "Admin reads all submissions" ON public.ai_learning_submissions
  FOR SELECT TO authenticated
  USING (public.is_master_admin());

-- ─── 3. Panel-level review (true / false per detected panel) ─────────────────
CREATE TABLE IF NOT EXISTS public.ai_learning_panel_reviews (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id  UUID NOT NULL REFERENCES public.ai_learning_submissions(id) ON DELETE CASCADE,
    panel_name     TEXT NOT NULL,
    ai_severity    TEXT,                        -- ringan | sedang | berat (as returned by AI)
    verdict        BOOLEAN NOT NULL,            -- true = AI panel is correct, false = wrong
    comment        TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (submission_id, panel_name)
);

ALTER TABLE public.ai_learning_panel_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Respondent manages own panel reviews" ON public.ai_learning_panel_reviews;
CREATE POLICY "Respondent manages own panel reviews" ON public.ai_learning_panel_reviews
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.ai_learning_submissions s
                 WHERE s.id = submission_id AND s.respondent_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.ai_learning_submissions s
                      WHERE s.id = submission_id AND s.respondent_id = auth.uid()));

DROP POLICY IF EXISTS "Admin reads all panel reviews" ON public.ai_learning_panel_reviews;
CREATE POLICY "Admin reads all panel reviews" ON public.ai_learning_panel_reviews
  FOR SELECT TO authenticated
  USING (public.is_master_admin());

-- ─── 4. Spare-part-level review (true / false per part within a panel) ──────
CREATE TABLE IF NOT EXISTS public.ai_learning_part_reviews (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id  UUID NOT NULL REFERENCES public.ai_learning_submissions(id) ON DELETE CASCADE,
    panel_name     TEXT NOT NULL,
    part_name      TEXT NOT NULL,
    verdict        BOOLEAN NOT NULL,            -- true = part is needed, false = not needed
    comment        TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (submission_id, panel_name, part_name)
);

ALTER TABLE public.ai_learning_part_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Respondent manages own part reviews" ON public.ai_learning_part_reviews;
CREATE POLICY "Respondent manages own part reviews" ON public.ai_learning_part_reviews
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.ai_learning_submissions s
                 WHERE s.id = submission_id AND s.respondent_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.ai_learning_submissions s
                      WHERE s.id = submission_id AND s.respondent_id = auth.uid()));

DROP POLICY IF EXISTS "Admin reads all part reviews" ON public.ai_learning_part_reviews;
CREATE POLICY "Admin reads all part reviews" ON public.ai_learning_part_reviews
  FOR SELECT TO authenticated
  USING (public.is_master_admin());
