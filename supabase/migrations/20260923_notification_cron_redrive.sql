-- ═══════════════════════════════════════════════════════════════════════════════
-- Retry pending notifications on a schedule
--
-- Before this, a failed dispatch was permanent. The INSERT trigger fires once,
-- and if that one call fails the row simply stays `pending` forever: the local
-- worker only sweeps `channel=whatsapp AND provider=bridge`, and nothing
-- invoked dispatch_pending_notifications(). Observed for real — 2 of 16 calls
-- to the edge function returned
--
--     HTTP 403 {"error":"forbidden"}
--
-- (the function could not resolve its expected dispatch secret for that
-- invocation, so it rejected the call). Each of those left an email row stuck
-- with no retry, which is silent loss: the notification is never delivered and
-- nothing ever tries again.
--
-- WHAT THIS ADDS
--
--   pg_cron            schedule every minute
--   notification_cron_drain(limit)   cron-safe re-drive wrapper
--
-- WHY A WRAPPER INSTEAD OF SCHEDULING dispatch_pending_notifications()
--
-- That function gates on is_master_admin(), which resolves auth.uid() from
-- request.jwt.claims. A pg_cron run carries no JWT, so the gate always fails.
-- Verified before scheduling it:
--
--     dispatch_pending_notifications() with no claims
--       RAISED 42501: only a platform admin may drain the notification queue
--
-- Scheduling it directly would therefore have failed on every single run while
-- looking perfectly healthy in cron.job. The wrapper has no JWT dependency, and
-- is instead locked to its owner: Supabase grants EXECUTE on a new public
-- function to anon/authenticated/service_role by default privilege, so those are
-- revoked explicitly — a bare REVOKE FROM PUBLIC does not remove them.
--
-- The schedule only ever handles RETRIES. The INSERT trigger still dispatches
-- immediately, so normal delivery is unaffected and stays prompt; this is the
-- safety net for failures and for anything queued while nothing was running.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. cron-safe re-drive ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notification_cron_drain(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id          uuid;
  v_dispatched  integer := 0;
  v_cfg         record;
BEGIN
  -- No is_master_admin() here on purpose — see the header. Access is controlled
  -- by the grants below instead, which is the only check that can work without a
  -- JWT.
  SELECT * INTO v_cfg FROM public.notification_config WHERE id = 1;
  IF v_cfg.id IS NULL
     OR NOT v_cfg.enabled
     OR COALESCE(v_cfg.dispatch_url, '') = '' THEN
    RETURN jsonb_build_object('dispatched', 0, 'reason', 'dispatch disabled or unconfigured');
  END IF;

  FOR v_id IN
    SELECT id FROM public.notification_outbox
     WHERE status = 'pending' AND attempts < 5
     ORDER BY created_at
     LIMIT GREATEST(1, LEAST(p_limit, 500))
  LOOP
    IF public.dispatch_notification(v_id) THEN
      v_dispatched := v_dispatched + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('dispatched', v_dispatched, 'at', now());
END;
$function$;

-- ─── 2. lock it to the owner ─────────────────────────────────────────────────
-- Without this the function is world-callable and anyone holding the publishable
-- key could repeatedly re-drive the queue. service_role is excluded too: the
-- local worker uses REST, not this RPC, and a net.http_post from outside would
-- be an SSRF-shaped write into the outbox.
REVOKE ALL ON FUNCTION public.notification_cron_drain(integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- ─── 3. schedule ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Every minute. cron.schedule is idempotent by job name: re-running the
-- migration updates the existing job rather than adding a duplicate.
SELECT cron.schedule(
  're-v-notification-redrive',
  '* * * * *',
  'SELECT public.notification_cron_drain(50)'
);

-- ─── 4. verification ─────────────────────────────────────────────────────────
WITH checks(ord, chk, got, want) AS (
  SELECT 1, 'pg_cron installed',
    (SELECT count(*)::text FROM pg_extension WHERE extname='pg_cron'), '1'
  UNION ALL SELECT 2, 'drain wrapper exists',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='notification_cron_drain'), '1'
  -- Must look at CODE lines only. The body contains the phrase 'is_master_admin'
  -- inside an explanatory comment, and a naive LIKE over pg_get_functiondef
  -- matches that comment — reporting a dependency that does not exist. Split into
  -- lines and ignore any line that is only a comment.
  UNION ALL SELECT 3, 'wrapper has NO auth.uid() dependency (must run under cron)',
    (SELECT (count(*) = 0)::text
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace,
       LATERAL regexp_split_to_table(pg_get_functiondef(p.oid), chr(10)) AS line
      WHERE n.nspname='public' AND p.proname='notification_cron_drain'
        AND btrim(line) NOT LIKE '--%'
        AND line LIKE '%is_master_admin%'), 'true'
  UNION ALL SELECT 4, 'anon cannot execute the wrapper',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='notification_cron_drain'
        AND grantee IN ('anon','authenticated','service_role')), '0'
  UNION ALL SELECT 5, 'the retry job is scheduled AND active',
    (SELECT count(*)::text FROM cron.job
      WHERE jobname='re-v-notification-redrive' AND active), '1'
  UNION ALL SELECT 6, 'job runs every minute',
    (SELECT (schedule = '* * * * *')::text FROM cron.job
      WHERE jobname='re-v-notification-redrive'), 'true'
  UNION ALL SELECT 7, 'dispatch trigger still present (prompt path unaffected)',
    (SELECT count(*)::text FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      WHERE c.relname='notification_outbox' AND t.tgname='on_notification_outbox_insert'
        AND t.tgenabled <> 'D'), '1'
)
SELECT CASE WHEN got = want THEN 'PASS' ELSE '*** FAIL ***' END AS result, chk, got, want
FROM checks ORDER BY ord;
