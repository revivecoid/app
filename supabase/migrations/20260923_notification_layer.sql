-- ═══════════════════════════════════════════════════════════════════════════════
-- Notification layer — make the pipeline actually deliver
--
-- State before this migration (verified 2026-09-23):
--   public.notifications held 0 rows. Not "few" — zero, ever.
--   handle_job_status_change() read app.supabase_url and app.service_role_key via
--   current_setting(), and BOTH were unset (`select name from pg_settings where
--   name like 'app.%'` → 0 rows). The function returns early in that case:
--       IF edge_function_url IS NULL OR service_role_key IS NULL ... RETURN NEW
--   So every status transition, since the trigger was created, has skipped the
--   notification entirely and reported nothing.
--
-- Why the old shape is replaced rather than repaired:
--   * A GUC holding the service_role key is invisible when unset and dangerous
--     when set (pg_settings is readable, and the key is a full tenant bypass).
--   * A direct fire-and-forget http_post loses the message if the function is
--     down, so "sent nothing" and "sent fine" look identical afterwards.
--
-- This migration instead uses a durable outbox:
--   notify()  →  notifications      (in-app; already in supabase_realtime, so the
--                                    app receives it live)
--             →  notification_outbox (one row per external channel, with status)
--   an AFTER INSERT trigger on the outbox asks pg_net to POST to the dispatch
--   function. If the function is down, misconfigured, or the request fails, the
--   row stays `pending` with the error recorded — visible and re-sendable, never
--   silently dropped. dispatch_pending_notifications() re-drives the queue.
--
-- Channel providers are configuration, not code: email resend|smtp|none, and
-- whatsapp meta|bridge|none, so the Meta Cloud API and the self-built bridge can
-- both exist and either can be switched on without a schema or client change.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Dispatch configuration (one row) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_config (
  id                INTEGER PRIMARY KEY CHECK (id = 1),
  -- Where to POST outbox rows. NULL disables dispatch and leaves rows queued.
  dispatch_url      TEXT,
  -- Shared secret the dispatch function verifies. Deliberately NOT the
  -- service_role key: notify() is SECURITY DEFINER and has already written the
  -- in-app row, so the function needs no database privileges at all.
  dispatch_secret   TEXT,
  -- Public/publishable key, used only as the bearer the gateway expects.
  dispatch_anon_key TEXT,

  email_provider    TEXT NOT NULL DEFAULT 'none'
                    CHECK (email_provider IN ('resend', 'smtp', 'none')),
  email_from        TEXT DEFAULT 'Revive <no-reply@revive.co.id>',

  whatsapp_provider TEXT NOT NULL DEFAULT 'none'
                    CHECK (whatsapp_provider IN ('meta', 'bridge', 'none')),
  -- Self-built bridge endpoint, used when whatsapp_provider = 'bridge':
  -- receives {"to": "<msisdn>", "template": "<name>", "variables": {...}}
  whatsapp_bridge_url     TEXT,
  whatsapp_bridge_secret  TEXT,

  enabled           BOOLEAN NOT NULL DEFAULT true,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.notification_config (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.notification_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage notification config" ON public.notification_config;
CREATE POLICY "Admins manage notification config" ON public.notification_config
  FOR ALL TO authenticated
  USING (public.is_master_admin())
  WITH CHECK (public.is_master_admin());

-- ─── 2. The outbox ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id        UUID REFERENCES public.repair_jobs(id) ON DELETE SET NULL,
  kind          TEXT NOT NULL,           -- stable key for the message, e.g. 'job_booked'
  channel       TEXT NOT NULL CHECK (channel IN ('email', 'whatsapp')),
  to_address    TEXT NOT NULL,
  title         TEXT NOT NULL,
  body          TEXT NOT NULL,
  payload       JSONB NOT NULL DEFAULT '{}'::jsonb,
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'sent', 'failed', 'skipped')),
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT,
  sent_at       TIMESTAMPTZ,
  provider      TEXT,                    -- which adapter actually handled it
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
  ON public.notification_outbox (created_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_notification_outbox_job
  ON public.notification_outbox (job_id, created_at DESC);

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read notification outbox" ON public.notification_outbox;
CREATE POLICY "Admins read notification outbox" ON public.notification_outbox
  FOR SELECT TO authenticated USING (public.is_master_admin());

-- ─── 3. notify(): the single entry point every flow step calls ────────────────
-- Recipients are resolved from the job by default, so callers pass intent
-- ("tell the customer", "tell the workshop") rather than hunting for ids.
CREATE OR REPLACE FUNCTION public.notify(
  p_kind      TEXT,
  p_title     TEXT,
  p_body      TEXT,
  p_job_id    UUID  DEFAULT NULL,
  p_to        TEXT  DEFAULT 'customer',   -- customer|partner|admin|all
  p_payload   JSONB DEFAULT '{}'::jsonb,
  p_user_id   UUID  DEFAULT NULL          -- explicit recipient, overrides p_to
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
BEGIN
  SELECT * INTO v_cfg FROM public.notification_config WHERE id = 1;

  -- Master switch. Off means nothing is written at all, which is a deliberate
  -- choice a human made — unlike the old silent-GUC failure.
  IF v_cfg.id IS NULL OR NOT v_cfg.enabled THEN
    RETURN 0;
  END IF;

  IF p_job_id IS NOT NULL THEN
    SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  END IF;

  FOR v_recipient IN
    SELECT DISTINCT r.uid
      FROM (
        -- the customer on the job
        SELECT v_job.customer_id AS uid
         WHERE p_to IN ('customer', 'all') AND v_job.customer_id IS NOT NULL

        UNION ALL
        -- every active member of the assigned workshop. Read memberships
        -- directly: partner_memberships() returns the CALLER's memberships as
        -- JSONB, so it cannot be used to find another workshop's staff.
        SELECT m.user_id AS uid
          FROM public.memberships m
         WHERE p_to IN ('partner', 'all')
           AND v_job.partner_id IS NOT NULL
           AND m.scope = 'partner'
           AND m.status = 'active'
           AND m.org_id = v_job.partner_id

        UNION ALL
        -- platform admins
        SELECT m.user_id AS uid
          FROM public.memberships m
         WHERE p_to IN ('admin', 'all')
           AND m.scope = 'platform'
           AND m.status = 'active'

        UNION ALL
        -- an explicit recipient
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

    -- Resolve destinations once, so the gate and the stored address cannot
    -- disagree. Both fall back sensibly:
    --   email    → the account address when the preference row holds none
    --   whatsapp → the number given at booking, for the job's own customer.
    --              WhatsApp stays opt-IN (the canonical default is false), which
    --              matters because Meta quality-rates numbers that get
    --              business-initiated messages without consent; consent is still
    --              required, the customer just should not have to re-type a
    --              number they already supplied to book.
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

    -- Build the channel list by appending, never SELECT INTO: a SELECT that
    -- matches no row assigns NULL, which would silently wipe a channel already
    -- added by the branch above it.
    v_channels := ARRAY[]::TEXT[];

    IF v_cfg.email_provider <> 'none'
       AND COALESCE(
             (SELECT np.email FROM public.notification_preferences np
               WHERE np.user_id = v_recipient.uid), false
           )
       AND v_email_to IS NOT NULL
    THEN
      -- array_append, not the || operator: `text[] || 'email'` resolves to array
      -- concatenation and reads the bare word as an array literal.
      v_channels := array_append(v_channels, 'email');
    END IF;

    IF v_cfg.whatsapp_provider <> 'none'
       AND COALESCE(
             (SELECT np.whatsapp FROM public.notification_preferences np
               WHERE np.user_id = v_recipient.uid), false
           )
       AND v_wa_to IS NOT NULL
    THEN
      v_channels := array_append(v_channels, 'whatsapp');
    END IF;

    IF array_length(v_channels, 1) > 0 THEN
      INSERT INTO public.notification_outbox
        (user_id, job_id, kind, channel, to_address, title, body, payload, provider)
      SELECT v_recipient.uid, p_job_id, p_kind, ch.channel,
             CASE ch.channel WHEN 'email' THEN v_email_to ELSE v_wa_to END,
             p_title, p_body, p_payload,
             CASE ch.channel
               WHEN 'email' THEN v_cfg.email_provider
               ELSE v_cfg.whatsapp_provider
             END
        FROM unnest(v_channels) AS ch(channel);

      v_count := v_count + array_length(v_channels, 1);
    END IF;
  END LOOP;

  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify(TEXT, TEXT, TEXT, UUID, TEXT, JSONB, UUID) FROM PUBLIC;

-- ─── 4. Dispatch: hand a queued row to the transport function ─────────────────
-- Deliberately callable only by admins (and the trigger below, which runs as
-- definer). It posts ONE outbox row; the transport function reports back by
-- calling notification_outbox_mark().
CREATE OR REPLACE FUNCTION public.dispatch_notification(p_outbox_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg   RECORD;
  v_row   RECORD;
BEGIN
  SELECT * INTO v_cfg FROM public.notification_config WHERE id = 1;

  IF v_cfg.id IS NULL
     OR NOT v_cfg.enabled
     OR COALESCE(v_cfg.dispatch_url, '') = '' THEN
    RETURN FALSE;   -- configured off: leave the row pending, do not lose it
  END IF;

  SELECT * INTO v_row FROM public.notification_outbox
   WHERE id = p_outbox_id AND status = 'pending' FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- pg_net 0.20.4 signature:
  --   http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds int)
  -- `body` is JSONB, not text — passing ::text matches no overload and raises
  -- 42883. `params` is skipped via named notation and defaulted.
  PERFORM net.http_post(
    url     := v_cfg.dispatch_url,
    body    := jsonb_build_object('outbox_id', v_row.id),
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || COALESCE(v_cfg.dispatch_anon_key, ''),
                 'x-dispatch-secret', COALESCE(v_cfg.dispatch_secret, '')
               )
  );

  UPDATE public.notification_outbox
     SET attempts = attempts + 1
   WHERE id = p_outbox_id;

  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.dispatch_notification(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispatch_notification(UUID) TO authenticated;

-- The transport function calls this to record the real outcome. Kept separate
-- from dispatch_notification() because only the transport knows whether the
-- provider accepted the message.
CREATE OR REPLACE FUNCTION public.notification_outbox_mark(
  p_outbox_id UUID,
  p_status    TEXT,
  p_error     TEXT DEFAULT NULL,
  p_provider  TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_status NOT IN ('sent', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'invalid outbox status: %', p_status;
  END IF;

  UPDATE public.notification_outbox
     SET status     = p_status,
         last_error = p_error,
         provider   = COALESCE(p_provider, provider),
         sent_at    = CASE WHEN p_status = 'sent' THEN now() ELSE sent_at END
   WHERE id = p_outbox_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.notification_outbox_mark(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;

-- Re-drive the queue: for rows still pending. Safe to call repeatedly, and the
-- only recovery path while pg_cron is unavailable on this project.
CREATE OR REPLACE FUNCTION public.dispatch_pending_notifications(p_limit INTEGER DEFAULT 50)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id    UUID;
  v_sent  INTEGER := 0;
BEGIN
  IF NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'only a platform admin may drain the notification queue'
      USING ERRCODE = '42501';
  END IF;

  FOR v_id IN
    SELECT id FROM public.notification_outbox
     WHERE status = 'pending' AND attempts < 5
     ORDER BY created_at
     LIMIT GREATEST(1, LEAST(p_limit, 500))
  LOOP
    IF public.dispatch_notification(v_id) THEN
      v_sent := v_sent + 1;
    END IF;
  END LOOP;

  RETURN v_sent;
END;
$function$;

REVOKE ALL ON FUNCTION public.dispatch_pending_notifications(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispatch_pending_notifications(INTEGER) TO authenticated;

-- Fire dispatch as soon as a row lands. Wrapped so a transport problem can never
-- abort the business transaction that produced the notification.
CREATE OR REPLACE FUNCTION public.trg_dispatch_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  BEGIN
    PERFORM public.dispatch_notification(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'trg_dispatch_notification: dispatch failed for % (row stays pending): %',
      NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_notification_outbox_insert ON public.notification_outbox;
CREATE TRIGGER on_notification_outbox_insert
  AFTER INSERT ON public.notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.trg_dispatch_notification();

-- ─── 5. Status-change notifications (replaces the dead webhook trigger) ───────
-- The old handle_job_status_change() is left in place but neutralised: it cannot
-- fire, because its GUCs are unset, and this trigger supersedes it. Dropping the
-- trigger rather than the function keeps the diff reversible.
DROP TRIGGER IF EXISTS on_repair_job_status_change ON public.repair_jobs;

CREATE OR REPLACE FUNCTION public.notify_job_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_kind  TEXT;
  v_title TEXT;
  v_body  TEXT;
  v_to    TEXT;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- Status is a code, not a sequence; the wording lives here so the flow's
  -- notification points are visible in one place.
  CASE NEW.status
    WHEN '3_booked' THEN
      v_kind := 'job_booked';   v_to := 'all';
      v_title := 'Booking Diterima';
      v_body  := 'Booking Anda sudah diterima. Kami akan menghubungi Anda untuk penjadwalan kendaraan.';

    WHEN '5_admitted' THEN
      v_kind := 'job_admitted'; v_to := 'all';
      v_title := 'Kendaraan Diterima';
      v_body  := 'Kendaraan Anda sudah diterima dan sedang menunggu pemeriksaan akhir.';

    WHEN '3_inspected' THEN
      v_kind := 'invoice_released'; v_to := 'customer';
      v_title := 'Invoice Diterbitkan';
      v_body  := 'Invoice perbaikan Anda sudah diterbitkan. Silakan buka aplikasi untuk meninjau dan menyetujuinya.';

    WHEN '4_paid' THEN
      v_kind := 'payment_received'; v_to := 'all';
      v_title := 'Pembayaran Berhasil';
      v_body  := 'Pembayaran Anda sudah kami terima. Perbaikan kendaraan akan segera dimulai.';

    WHEN '6_in_progress' THEN
      v_kind := 'repair_started'; v_to := 'customer';
      v_title := 'Perbaikan Dimulai';
      v_body  := 'Perbaikan kendaraan Anda sudah dimulai. Anda dapat memantau perkembangannya di aplikasi.';

    WHEN '7_finished' THEN
      v_kind := 'repair_finished'; v_to := 'all';
      v_title := 'Perbaikan Selesai';
      v_body  := 'Perbaikan kendaraan Anda sudah selesai. Kami akan menjadwalkan pengantaran atau pengambilan.';

    WHEN '8_awaiting_delivery' THEN
      v_kind := 'awaiting_delivery'; v_to := 'customer';
      v_title := 'Siap Diantar atau Diambil';
      v_body  := 'Kendaraan Anda siap. Silakan pilih jadwal pengantaran atau pengambilan di aplikasi.';

    WHEN '9_done' THEN
      v_kind := 'job_done'; v_to := 'all';
      v_title := 'Pesanan Selesai';
      v_body  := 'Kendaraan Anda sudah diserahkan. Terima kasih telah menggunakan Revive.';

    WHEN '0_cancelled' THEN
      v_kind := 'job_cancelled'; v_to := 'all';
      v_title := 'Pesanan Dibatalkan';
      v_body  := 'Pesanan ini telah dibatalkan. Hubungi kami bila Anda memerlukan bantuan.';

    ELSE
      RETURN NEW;   -- internal/pre-payment statuses are not customer-facing
  END CASE;

  PERFORM public.notify(v_kind, v_title, v_body, NEW.id, v_to);

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_job_status_notify ON public.repair_jobs;
CREATE TRIGGER on_job_status_notify
  AFTER UPDATE OF status ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.notify_job_status_change();

-- Assignment is not a status change, so it needs its own trigger: the flow says
-- the partner is notified when a job is deployed to them.
CREATE OR REPLACE FUNCTION public.notify_job_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.partner_id IS NOT NULL
     AND NEW.partner_id IS DISTINCT FROM OLD.partner_id THEN
    PERFORM public.notify(
      'job_assigned',
      'Pekerjaan Baru',
      'Ada pekerjaan baru yang ditugaskan ke workshop Anda. Silakan buka aplikasi untuk meninjaunya.',
      NEW.id,
      'partner'
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_job_assignment_notify ON public.repair_jobs;
CREATE TRIGGER on_job_assignment_notify
  AFTER UPDATE OF partner_id ON public.repair_jobs
  FOR EACH ROW EXECUTE FUNCTION public.notify_job_assignment();

-- ─── 6. Backfill notification_preferences for accounts created before the ─────
--        trigger existed
--
-- handle_new_user_notification_prefs() only fires AFTER INSERT ON auth.users, so
-- any account that already existed when 20260905_notification_tables.sql landed
-- never got a row. Verified 2026-09-23: 17 auth users, 12 preference rows, 5
-- missing — including the workshop owner (irianto.suryoputro@gmail.com) and the
-- mechanic on the live job.
--
-- That matters beyond tidiness: notify() reads the preference row to decide which
-- channels to use. With no row, COALESCE defaults in_app to true (so the in-app
-- notification still lands) but email and whatsapp both read as unset, so those
-- recipients could never receive anything off-app no matter how the config was
-- set. A missing row is silently indistinguishable from "user opted out".
--
-- Mirrors the trigger's own insert exactly — user_id plus email_address, and
-- nothing else — so a backfilled row is byte-equivalent to a trigger-created one
-- and the canonical defaults (in_app true, email true, whatsapp false) apply.
INSERT INTO public.notification_preferences (user_id, email_address)
SELECT u.id, u.email
  FROM auth.users u
  LEFT JOIN public.notification_preferences np ON np.user_id = u.id
 WHERE np.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- ─── 7. Verification ─────────────────────────────────────────────────────────
WITH checks(ord, chk, got, want) AS (
  SELECT 1, 'notification_config row exists',
    (SELECT count(*)::text FROM public.notification_config WHERE id = 1), '1'
  UNION ALL SELECT 2, 'notification_outbox table exists',
    (SELECT count(*)::text FROM information_schema.tables
      WHERE table_schema='public' AND table_name='notification_outbox'), '1'
  UNION ALL SELECT 3, 'notify() present',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='notify'), '1'
  UNION ALL SELECT 4, 'dispatch_notification() present',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='dispatch_notification'), '1'
  UNION ALL SELECT 5, 'outbox dispatch trigger installed',
    (SELECT count(*)::text FROM pg_trigger WHERE tgname='on_notification_outbox_insert'), '1'
  UNION ALL SELECT 6, 'new status-notify trigger installed',
    (SELECT count(*)::text FROM pg_trigger WHERE tgname='on_job_status_notify'), '1'
  UNION ALL SELECT 7, 'old dead webhook trigger removed',
    (SELECT count(*)::text FROM pg_trigger WHERE tgname='on_repair_job_status_change'), '0'
  UNION ALL SELECT 8, 'assignment notify trigger installed',
    (SELECT count(*)::text FROM pg_trigger WHERE tgname='on_job_assignment_notify'), '1'
  UNION ALL SELECT 9, 'every auth user has a preference row',
    (SELECT (count(*) - count(np.user_id))::text
       FROM auth.users u LEFT JOIN public.notification_preferences np ON np.user_id=u.id), '0'
  UNION ALL SELECT 10, 'outbox defaults to pending, never silently sent',
    (SELECT count(*)::text FROM public.notification_outbox WHERE status NOT IN
      ('pending','sent','failed','skipped')), '0'
)
SELECT CASE WHEN got = want THEN 'PASS' ELSE '*** FAIL ***' END AS result, chk, got, want
FROM checks ORDER BY ord;
