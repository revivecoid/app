-- =============================================================================
-- Migration: Add estimation_result JSONB to repair_jobs
-- Date: 2026-09-18
-- Purpose: Persist the full AI structuredData so the booking screen can
--          display the damage breakdown and cost summary after navigation.
--          Previously this lived only in widget state and was lost on pop.
-- =============================================================================

ALTER TABLE public.repair_jobs
  ADD COLUMN IF NOT EXISTS estimation_result JSONB;

COMMENT ON COLUMN public.repair_jobs.estimation_result IS
  'Full structuredData JSON from the vision-estimation edge function. '
  'Contains assessment.damaged_panels_detail, financial_estimation, analysis_metadata.';

-- Index for any future queries that filter/sort on estimation data
CREATE INDEX IF NOT EXISTS idx_repair_jobs_estimation_result
  ON public.repair_jobs USING GIN (estimation_result)
  WHERE estimation_result IS NOT NULL;
