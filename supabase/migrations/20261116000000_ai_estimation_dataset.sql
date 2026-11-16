-- Training corpus capture: every job that reaches a real invoice keeps the
-- estimator's structured output, the R2 keys of the photos the model judged,
-- and the workshop's final cost. That row is the labelled pair a later
-- fine-tune (or the few-shot prompt) feeds on.
--
-- Deliberately NOT auto-promoted into ai_training_context: that table is
-- injected into the live prompt, so only reviewed cases may land there
-- (promoted_case_id records the link once a human promotes the row).

CREATE TABLE IF NOT EXISTS public.ai_estimation_dataset (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                  UUID NOT NULL UNIQUE REFERENCES public.repair_jobs(id) ON DELETE CASCADE,
    customer_id             UUID,
    partner_id              UUID,
    vehicle_id              UUID,
    car_make_model          TEXT,
    photo_keys              TEXT[] NOT NULL DEFAULT '{}',
    structured_data         JSONB NOT NULL DEFAULT '{}'::JSONB,
    initial_estimation_cost NUMERIC,
    final_cost              NUMERIC,
    status                  TEXT,
    is_training_ready       BOOLEAN NOT NULL DEFAULT FALSE,
    promoted_case_id        UUID REFERENCES public.ai_training_context(id) ON DELETE SET NULL,
    source                  TEXT NOT NULL DEFAULT 'job_final_cost',
    captured_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_estimation_dataset_ready
    ON public.ai_estimation_dataset (is_training_ready, captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_estimation_dataset_car
    ON public.ai_estimation_dataset (car_make_model);

ALTER TABLE public.ai_estimation_dataset ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Master admin reads estimation dataset" ON public.ai_estimation_dataset;
CREATE POLICY "Master admin reads estimation dataset" ON public.ai_estimation_dataset
    FOR SELECT TO authenticated
    USING (public.is_master_admin());

-- ─── Capture on invoice ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.capture_estimation_dataset()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_photo_keys TEXT[];
    v_car        TEXT;
BEGIN
    v_photo_keys := COALESCE(
        ARRAY(
            SELECT jsonb_array_elements_text(
                COALESCE(NEW.estimation_result -> 'source_photos' -> 'keys', '[]'::JSONB)
            )
        ),
        '{}'::TEXT[]
    );

    SELECT NULLIF(TRIM(CONCAT_WS(' ', make, model, year)), '')
      INTO v_car
      FROM public.vehicles
     WHERE id = NEW.vehicle_id;

    INSERT INTO public.ai_estimation_dataset (
        job_id, customer_id, partner_id, vehicle_id, car_make_model,
        photo_keys, structured_data, initial_estimation_cost, final_cost,
        status, is_training_ready
    ) VALUES (
        NEW.id, NEW.customer_id, NEW.partner_id, NEW.vehicle_id, v_car,
        v_photo_keys, COALESCE(NEW.estimation_result, '{}'::JSONB),
        NEW.initial_estimation_cost, NEW.final_cost, NEW.status,
        (COALESCE(NEW.final_cost, 0) > 0 AND COALESCE(array_length(v_photo_keys, 1), 0) > 0)
    )
    ON CONFLICT (job_id) DO UPDATE SET
        partner_id        = EXCLUDED.partner_id,
        car_make_model    = COALESCE(EXCLUDED.car_make_model, public.ai_estimation_dataset.car_make_model),
        photo_keys        = EXCLUDED.photo_keys,
        structured_data   = EXCLUDED.structured_data,
        final_cost        = EXCLUDED.final_cost,
        status            = EXCLUDED.status,
        is_training_ready = EXCLUDED.is_training_ready,
        updated_at        = NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS capture_estimation_dataset_trg ON public.repair_jobs;
CREATE TRIGGER capture_estimation_dataset_trg
    AFTER INSERT OR UPDATE ON public.repair_jobs
    FOR EACH ROW
    WHEN (NEW.final_cost IS NOT NULL AND NEW.final_cost > 0)
    EXECUTE FUNCTION public.capture_estimation_dataset();

COMMENT ON TABLE public.ai_estimation_dataset IS
    'One row per invoiced job: estimator output + photo keys + final cost. Training corpus for future fine-tuning and few-shot promotion into ai_training_context.';
COMMENT ON COLUMN public.ai_estimation_dataset.photo_keys IS
    'Durable R2 object keys (bucket revive-photos), derived from the presigned URLs the model was given.';
COMMENT ON COLUMN public.ai_estimation_dataset.is_training_ready IS
    'TRUE when the job has a final cost and at least one photo key — usable as a labelled pair as-is.';
