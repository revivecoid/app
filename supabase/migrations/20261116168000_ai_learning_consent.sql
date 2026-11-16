-- The AI-learning respondents contributed photos and estimates with no
-- recorded consent and no way to withdraw it.
--
-- The profile form said nothing about training data, and once a photo was
-- uploaded there was no owner-level record of who agreed to what. This adds a
-- durable consent record keyed by (user, document, version) plus the RPCs the
-- client needs to grant and withdraw it.

CREATE TABLE IF NOT EXISTS public.consent_records (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doc          text NOT NULL,
  version      text NOT NULL DEFAULT '1.0',
  granted_at   timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz,
  ip_hint      text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, doc, version)
);

ALTER TABLE public.consent_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read their own consent" ON public.consent_records;
CREATE POLICY "Users read their own consent"
  ON public.consent_records FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins read all consent" ON public.consent_records;
CREATE POLICY "Admins read all consent"
  ON public.consent_records FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid() AND p.role = 'master_admin'
  ));

-- No INSERT/UPDATE policy: writes go through the RPCs below, which stamp
-- auth.uid() so a user can never grant consent on someone else's behalf.

CREATE OR REPLACE FUNCTION public.record_consent(p_doc text, p_version text DEFAULT '1.0')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHORIZED');
  END IF;
  IF p_doc IS NULL OR length(p_doc) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'VALIDATION: doc required');
  END IF;

  INSERT INTO public.consent_records (user_id, doc, version, granted_at, revoked_at)
  VALUES (v_uid, p_doc, COALESCE(p_version, '1.0'), now(), NULL)
  ON CONFLICT (user_id, doc, version) DO UPDATE
    SET granted_at = now(),
        revoked_at = NULL;

  RETURN jsonb_build_object('ok', true, 'doc', p_doc, 'version',
                            COALESCE(p_version, '1.0'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_consent(p_doc text, p_version text DEFAULT '1.0')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHORIZED');
  END IF;

  UPDATE public.consent_records
     SET revoked_at = now()
   WHERE user_id = v_uid
     AND doc = p_doc
     AND version = COALESCE(p_version, '1.0')
     AND revoked_at IS NULL;

  -- Withdrawal must also stop the data from feeding future training runs.
  -- ai_learning_submissions keys the owner as respondent_id (FK to
  -- ai_learning_respondents.user_id), not user_id.
  IF p_doc = 'ai_learning' THEN
    UPDATE public.ai_learning_submissions
       SET excluded_from_training = true
     WHERE respondent_id = v_uid;
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$function$;

-- Fast lookup for "did this user consent" checks server-side.
CREATE OR REPLACE FUNCTION public.has_consent(p_doc text, p_version text DEFAULT '1.0')
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.consent_records c
     WHERE c.user_id = auth.uid()
       AND c.doc = p_doc
       AND c.version = COALESCE(p_version, '1.0')
       AND c.revoked_at IS NULL
  );
$function$;

-- Enforcement, not just a checkbox: a submission is refused unless the
-- respondent has live consent. A client that skips the form cannot slip data
-- into the training set.
CREATE OR REPLACE FUNCTION public.guard_learning_submission_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.consent_records c
     WHERE c.user_id = NEW.respondent_id
       AND c.doc = 'ai_learning'
       AND c.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CONSENT_REQUIRED: respondent has not consented to AI training use'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_learning_submission_consent ON public.ai_learning_submissions;
CREATE TRIGGER trg_guard_learning_submission_consent
  BEFORE INSERT ON public.ai_learning_submissions
  FOR EACH ROW EXECUTE FUNCTION public.guard_learning_submission_consent();

-- Column the withdrawal path writes to. Guarded because older databases may
-- not have the column yet.
ALTER TABLE public.ai_learning_submissions
  ADD COLUMN IF NOT EXISTS excluded_from_training boolean NOT NULL DEFAULT false;
