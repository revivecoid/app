-- ═══════════════════════════════════════════════════════════════════════════════
-- Two WhatsApp providers, routed by purpose
--
-- re-V needs two WhatsApp numbers doing different jobs:
--
--   +62 811 2223 1235   notifications and marketing   → Meta Cloud API
--   (second number)     chatbot                       → self-built Baileys bridge
--
-- Why split rather than pick one:
--   * Meta Cloud API is sanctioned and serverless. It is the right transport for
--     transactional notifications and for marketing broadcasts.
--   * A Baileys bridge is an unofficial consumer-account automation. It is the
--     only route that supports the free-form, bidirectional messaging a chatbot
--     needs, but it carries real ban risk — so it must not be the transport for
--     anything customer-critical.
--
-- Before this, `notify()` read a single `whatsapp_provider` for every message.
-- With two numbers in play that becomes a live hazard: a marketing broadcast or
-- a customer notification could be dispatched through the consumer chatbot
-- account and get that number banned, and a chatbot reply could leave from the
-- official business number. Routing is therefore made explicit and recorded per
-- row, not inferred.
--
-- WHAT THIS MIGRATION DOES NOT DO
--
-- It builds the transport registry and the routing, not the chatbot. A chatbot
-- needs an inbound path — a webhook receiving the customer's messages, some
-- conversation state, and reply generation. `notify(..., p_channel := 'chatbot')`
-- covers only OUTBOUND pushes from the chatbot number (e.g. "your car is ready,
-- reply here"). Inbound handling is separate work.
--
-- Also added: `notification_preferences.whatsapp_marketing`. Marketing to a
-- WhatsApp number without recorded consent is what gets a number quality-rated
-- and blocked, so a marketing send now requires an explicit opt-in that is
-- separate from the transactional one. Default false — nobody is opted in until
-- they say so.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Config: the chatbot transport, separate from the notif transport ──────
ALTER TABLE public.notification_config
  ADD COLUMN IF NOT EXISTS whatsapp_chatbot_provider TEXT NOT NULL DEFAULT 'none';

ALTER TABLE public.notification_config
  ADD COLUMN IF NOT EXISTS whatsapp_chatbot_bridge_url TEXT;

-- Named check constraint so re-running is safe (ADD CONSTRAINT has no IF NOT EXISTS).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_config_chatbot_provider_check'
  ) THEN
    ALTER TABLE public.notification_config
      ADD CONSTRAINT notification_config_chatbot_provider_check
      CHECK (whatsapp_chatbot_provider IN ('meta', 'bridge', 'none'));
  END IF;
END $$;

-- The two numbers are separate WhatsApp sessions, so a bridge-based number needs
-- its own URL. Two bridge numbers = two processes on two ports, not one URL.
COMMENT ON COLUMN public.notification_config.whatsapp_bridge_url IS
  'Bridge URL for the NOTIFICATION number when whatsapp_provider = ''bridge''. '
  'Unused while notifications go through Meta.';
COMMENT ON COLUMN public.notification_config.whatsapp_chatbot_bridge_url IS
  'Bridge URL for the CHATBOT number. A separate Baileys session from the '
  'notification number, so it is a separate URL/port.';

-- ─── 2. Marketing consent, separate from transactional ───────────────────────
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS whatsapp_marketing BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS email_marketing BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.notification_preferences.whatsapp_marketing IS
  'Opt-in for WhatsApp marketing broadcasts. Deliberately separate from '
  '`whatsapp`, which covers transactional job notifications: agreeing to be told '
  'your car is ready is not agreeing to receive promotions. Defaults false.';
COMMENT ON COLUMN public.notification_preferences.email_marketing IS
  'Opt-in for email marketing. Separate from `email` for the same reason, and '
  'separate from `whatsapp_marketing` because consent given on one channel is not '
  'consent on another. Defaults false.';

-- ─── 3. Outbox: record why a message was sent, not just how ───────────────────
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS purpose TEXT NOT NULL DEFAULT 'transactional';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notification_outbox_purpose_check'
  ) THEN
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox_purpose_check
      CHECK (purpose IN ('transactional', 'marketing', 'chatbot'));
  END IF;
END $$;

-- The drain worker filters on purpose, so it gets its own index rather than
-- scanning the transactional backlog it does not handle.
CREATE INDEX IF NOT EXISTS idx_notification_outbox_purpose_pending
  ON public.notification_outbox (purpose, created_at)
  WHERE status = 'pending';

-- ─── 4. notify() v2: pick the transport from the purpose ─────────────────────
-- p_channel is appended LAST so every existing positional call site — the two
-- status/assignment triggers and the invoice RPCs — keeps working unchanged.
CREATE OR REPLACE FUNCTION public.notify(
  p_kind      TEXT,
  p_title     TEXT,
  p_body      TEXT,
  p_job_id    UUID  DEFAULT NULL,
  p_to        TEXT  DEFAULT 'customer',
  p_payload   JSONB DEFAULT '{}'::jsonb,
  p_user_id   UUID  DEFAULT NULL,
  p_channel   TEXT  DEFAULT 'system'   -- system | marketing | chatbot
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg        RECORD;
  v_job        RECORD;
  v_recipient  RECORD;
  v_count      INTEGER := 0;
  v_channels   TEXT[];
  v_email_to   TEXT;
  v_wa_to      TEXT;
  v_purpose    TEXT;
  v_wa_provider TEXT;
BEGIN
  IF p_channel NOT IN ('system', 'marketing', 'chatbot') THEN
    RAISE EXCEPTION 'unknown channel %, expected system|marketing|chatbot', p_channel
      USING ERRCODE = '22023';
  END IF;

  v_purpose := CASE p_channel
                 WHEN 'chatbot'   THEN 'chatbot'
                 WHEN 'marketing' THEN 'marketing'
                 ELSE 'transactional'
               END;

  SELECT * INTO v_cfg FROM public.notification_config WHERE id = 1;

  -- Master switch. Off means nothing is written at all, which is a deliberate
  -- choice a human made — unlike the old silent-GUC failure.
  IF v_cfg.id IS NULL OR NOT v_cfg.enabled THEN
    RETURN 0;
  END IF;

  -- The transport follows the purpose. This is the line that keeps a marketing
  -- broadcast off the consumer chatbot number and a chatbot reply off the
  -- official business number.
  v_wa_provider := CASE
                     WHEN v_purpose = 'chatbot' THEN v_cfg.whatsapp_chatbot_provider
                     ELSE v_cfg.whatsapp_provider
                   END;

  -- Unconditional on purpose. `SELECT ... INTO` assigns the record even when it
  -- matches no row (all fields NULL), so `v_job.customer_id` below is safe to
  -- read. The previous version guarded this with `IF p_job_id IS NOT NULL`, which
  -- left v_job UNASSIGNED for a job-less notification — and reading any field of
  -- an unassigned record raises:
  --
  --     55000: record "v_job" is not assigned yet
  --
  -- That made every job-less call fail, which is every marketing broadcast and
  -- every chatbot push. Their own job id is irrelevant to the recipient lookup,
  -- but the reference still executes.
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;

  FOR v_recipient IN
    SELECT DISTINCT r.uid
      FROM (
        SELECT v_job.customer_id AS uid
         WHERE p_to IN ('customer', 'all') AND v_job.customer_id IS NOT NULL

        UNION ALL
        SELECT m.user_id AS uid
          FROM public.memberships m
         WHERE p_to IN ('partner', 'all')
           AND v_job.partner_id IS NOT NULL
           AND m.scope = 'partner'
           AND m.status = 'active'
           AND m.org_id = v_job.partner_id

        UNION ALL
        SELECT m.user_id AS uid
          FROM public.memberships m
         WHERE p_to IN ('admin', 'all')
           AND m.scope = 'platform'
           AND m.status = 'active'

        UNION ALL
        SELECT p_user_id AS uid WHERE p_user_id IS NOT NULL
      ) r
     WHERE r.uid IS NOT NULL
  LOOP
    -- In-app: honour the user's preference, defaulting to on when unset.
    IF COALESCE(
         (SELECT np.in_app FROM public.notification_preferences np
           WHERE np.user_id = v_recipient.uid), true
       )
    THEN
      INSERT INTO public.notifications (user_id, job_id, title, body, type, is_read)
      VALUES (v_recipient.uid, p_job_id, p_title, p_body, p_kind, false);
      v_count := v_count + 1;
    END IF;

    v_email_to := COALESCE(
      (SELECT NULLIF(np.email_address, '') FROM public.notification_preferences np
        WHERE np.user_id = v_recipient.uid),
      (SELECT NULLIF(u.email, '') FROM auth.users u WHERE u.id = v_recipient.uid)
    );

    v_wa_to := COALESCE(
      (SELECT NULLIF(np.whatsapp_number, '') FROM public.notification_preferences np
        WHERE np.user_id = v_recipient.uid),
      CASE WHEN v_job.customer_id = v_recipient.uid THEN NULLIF(v_job.contact_phone, '') END
    );

    v_channels := ARRAY[]::TEXT[];

    -- Marketing goes out on email too, but only with marketing consent on EMAIL.
    -- Consent is per channel: someone who agreed to WhatsApp promotions has not
    -- agreed to email ones, and treating them as interchangeable is how a list
    -- gets reported as spam.
    IF v_cfg.email_provider <> 'none'
       AND v_email_to IS NOT NULL
       -- The CASE must be parenthesised: plpgsql's parser cannot handle a bare
       -- `CASE ... END` in an IF condition, and reports it as
       -- "syntax error at end of input" pointing at the CASE keyword.
       AND (CASE
             WHEN v_purpose = 'marketing' THEN COALESCE(
               (SELECT np.email AND np.email_marketing
                  FROM public.notification_preferences np
                 WHERE np.user_id = v_recipient.uid), false)
             ELSE COALESCE(
               (SELECT np.email FROM public.notification_preferences np
                 WHERE np.user_id = v_recipient.uid), false)
           END)
    THEN
      v_channels := array_append(v_channels, 'email');
    END IF;

    -- WhatsApp. Marketing requires the marketing opt-in specifically; everything
    -- else uses the transactional one. An unknown/unset preference row reads as
    -- NOT consented, so a missing row can never be treated as a yes.
    IF v_wa_provider <> 'none'
       AND v_wa_to IS NOT NULL
       AND (CASE
             WHEN v_purpose = 'marketing' THEN COALESCE(
               (SELECT np.whatsapp_marketing
                  FROM public.notification_preferences np
                 WHERE np.user_id = v_recipient.uid), false)
             ELSE COALESCE(
               (SELECT np.whatsapp FROM public.notification_preferences np
                 WHERE np.user_id = v_recipient.uid), false)
           END)
    THEN
      v_channels := array_append(v_channels, 'whatsapp');
    END IF;

    IF array_length(v_channels, 1) > 0 THEN
      INSERT INTO public.notification_outbox
        (user_id, job_id, kind, channel, to_address, title, body, payload,
         provider, purpose)
      SELECT v_recipient.uid, p_job_id, p_kind, ch.channel,
             CASE ch.channel WHEN 'email' THEN v_email_to ELSE v_wa_to END,
             p_title, p_body, p_payload,
             CASE ch.channel
               WHEN 'email' THEN v_cfg.email_provider
               ELSE v_wa_provider
             END,
             v_purpose
        FROM unnest(v_channels) AS ch(channel);

      v_count := v_count + array_length(v_channels, 1);
    END IF;
  END LOOP;

  RETURN v_count;
END;
$function$;

-- CREATE OR REPLACE cannot change a signature: with a new argument list it creates
-- an OVERLOAD, leaving the old 7-arg notify() in place beside the new 8-arg one.
-- That is not harmless. A call with five arguments — exactly what
-- notify_job_status_change() and notify_job_assignment() do — then matches both
-- candidates and Postgres raises:
--
--     42725: function public.notify(...) is not unique
--
-- and because the failed call sits inside a trigger, it aborts the whole
-- statement: every job status change, admission, invoice release and payment
-- would roll back, not just lose its notification. So the 7-arg version is
-- dropped explicitly. It happens after the 8-arg one is created, so there is
-- never a moment with no notify() at all.
DROP FUNCTION IF EXISTS public.notify(TEXT, TEXT, TEXT, UUID, TEXT, JSONB, UUID);

-- Triggers call this as the table owner; no API role needs EXECUTE. Re-stated
-- because Supabase grants EXECUTE to anon/authenticated by default privilege and
-- a bare REVOKE FROM PUBLIC does not remove those.
REVOKE EXECUTE ON FUNCTION public.notify(TEXT, TEXT, TEXT, UUID, TEXT, JSONB, UUID, TEXT)
  FROM anon, authenticated;

-- ─── 5. Marketing broadcast, admin-only and consent-gated ────────────────────
-- Enqueues one purpose='marketing' message per recipient who has actually opted
-- in. Returns a breakdown so an admin can see how many were skipped and why,
-- rather than guessing why a "successful" send reached 12 of 400 people.
CREATE OR REPLACE FUNCTION public.enqueue_marketing_broadcast(
  p_kind    TEXT,
  p_title   TEXT,
  p_body    TEXT,
  p_only_opted_in BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg        RECORD;
  v_recipient  RECORD;
  v_queued     INTEGER := 0;
  v_skipped    INTEGER := 0;
  v_no_address INTEGER := 0;
BEGIN
  IF NOT public.is_master_admin() THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Only a platform admin can send a marketing broadcast.');
  END IF;

  SELECT * INTO v_cfg FROM public.notification_config WHERE id = 1;
  IF v_cfg.id IS NULL OR NOT v_cfg.enabled THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notifications are disabled.');
  END IF;
  IF v_cfg.whatsapp_provider = 'none' AND v_cfg.email_provider = 'none' THEN
    RETURN jsonb_build_object('success', false,
      'error', 'No marketing transport is configured (email and whatsapp both none).');
  END IF;

  -- Iterate every user who has a preference row. Users with no row are excluded
  -- rather than defaulted in: broadcast consent must be explicit, and a missing
  -- row means nobody ever asked them.
  FOR v_recipient IN
    SELECT np.user_id, np.whatsapp_number, np.email_address,
           np.whatsapp_marketing, np.email_marketing, np.email, np.in_app
      FROM public.notification_preferences np
  LOOP
    -- Skip only when there is no marketing consent on ANY channel. A user who
    -- opted in to email marketing but not WhatsApp must still be reachable by
    -- email, so the gate is "consent anywhere", not "consent on WhatsApp".
    IF p_only_opted_in
       AND NOT COALESCE(v_recipient.whatsapp_marketing, false)
       AND NOT COALESCE(v_recipient.email_marketing, false) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Reuse notify() so the routing, consent mapping and outbox write live in one
    -- place. p_to is unused here because the recipient is explicit.
    IF public.notify(p_kind, p_title, p_body, NULL, 'customer', '{}'::jsonb,
                     v_recipient.user_id, 'marketing') > 0
    THEN
      v_queued := v_queued + 1;
    ELSE
      v_no_address := v_no_address + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true, 'queued', v_queued,
    'skipped_no_consent', v_skipped, 'skipped_no_address', v_no_address,
    'purpose', 'marketing');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.enqueue_marketing_broadcast(TEXT, TEXT, TEXT, BOOLEAN)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_marketing_broadcast(TEXT, TEXT, TEXT, BOOLEAN)
  TO authenticated;   -- the RPC checks is_master_admin() itself

-- ─── 6. Verification ─────────────────────────────────────────────────────────
WITH checks(ord, chk, got, want) AS (
  SELECT 1, 'chatbot provider column added',
    (SELECT count(*)::text FROM information_schema.columns
      WHERE table_schema='public' AND table_name='notification_config'
        AND column_name='whatsapp_chatbot_provider'), '1'
  UNION ALL SELECT 2, 'chatbot bridge url column added',
    (SELECT count(*)::text FROM information_schema.columns
      WHERE table_schema='public' AND table_name='notification_config'
        AND column_name='whatsapp_chatbot_bridge_url'), '1'
  UNION ALL SELECT 3, 'marketing consent column added, defaults false',
    (SELECT (count(*) = 1)::text FROM information_schema.columns
      WHERE table_schema='public' AND table_name='notification_preferences'
        AND column_name='whatsapp_marketing' AND column_default = 'false'), 'true'
  UNION ALL SELECT 4, 'outbox purpose column added',
    (SELECT count(*)::text FROM information_schema.columns
      WHERE table_schema='public' AND table_name='notification_outbox'
        AND column_name='purpose'), '1'
  UNION ALL SELECT 5, 'purpose constraint installed',
    (SELECT count(*)::text FROM pg_constraint
      WHERE conname='notification_outbox_purpose_check'), '1'
  UNION ALL SELECT 6, 'notify() has exactly ONE overload (no ambiguity for 5-arg calls)',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='notify'), '1'
  UNION ALL SELECT 7, 'that notify() takes p_channel and routes by purpose',
    (SELECT (pg_get_function_arguments(p.oid) LIKE '%p_channel%'
             AND pg_get_functiondef(p.oid) LIKE '%v_wa_provider := CASE%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='notify' LIMIT 1), 'true'
  UNION ALL SELECT 12, 'the 5-arg call the triggers use still resolves',
    (SELECT (to_regprocedure(
        'public.notify(text,text,text,uuid,text,jsonb,uuid,text)') IS NOT NULL
      AND to_regprocedure('public.notify(text,text,text,uuid,text,jsonb,uuid)') IS NULL)::text),
    'true'
  UNION ALL SELECT 8, 'marketing broadcast fn present',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='enqueue_marketing_broadcast'), '1'
  UNION ALL SELECT 9, 'anon cannot call notify()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='notify'
        AND grantee IN ('anon','authenticated')), '0'
  UNION ALL SELECT 10, 'anon cannot call the marketing broadcast',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='enqueue_marketing_broadcast'
        AND grantee='anon'), '0'
  UNION ALL SELECT 11, 'existing notification config preserved',
    (SELECT count(*)::text FROM public.notification_config WHERE id=1), '1'
)
SELECT CASE WHEN got = want THEN 'PASS' ELSE '*** FAIL ***' END AS result, chk, got, want
FROM checks ORDER BY ord;
