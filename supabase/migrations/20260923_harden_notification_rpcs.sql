-- ═══════════════════════════════════════════════════════════════════════════════
-- Harden public RPCs against anon/authenticated
--
-- Found by reading information_schema.routine_privileges after the notification
-- and invoice work went live — NOT by assuming the REVOKEs in those migrations
-- had worked. They had not, and the reason is a Supabase default worth knowing:
--
--   Supabase ships ALTER DEFAULT PRIVILEGES granting EXECUTE on every function
--   created in `public` to anon, authenticated and service_role as EXPLICIT role
--   grants. `REVOKE ALL ... FROM PUBLIC` removes only the implicit PUBLIC grant
--   and leaves those three intact. So a function can look locked down in its
--   migration and still be callable with nothing but the publishable key.
--
--   Confirmed live: 48 of the schema's functions were anon-executable, including
--   notify(), notification_outbox_mark(), get_invoice_for_job() and the
--   pre-existing get_customer_jobs().
--
-- Most of the older ones are SECURITY DEFINER with an internal is_master_admin()
-- check, so being callable is not the same as being exploitable. Those are left
-- alone deliberately — re-granting 40-odd functions is a large, risky change and
-- this migration exists to fix specific holes, not to reform the schema.
--
-- THE HOLES FIXED HERE
--
-- 1. notify() — no internal check (by design: it is called by triggers). As anon,
--    any visitor could call notify(..., p_job_id, 'all') and push a fabricated
--    message to that job's customer, its workshop and every platform admin. It is
--    SECURITY DEFINER, so it wrote rows the caller had no right to write. At best
--    spam; with a crafted title and body it is a phishing channel delivered by the
--    platform's own notification desk.
--
-- 2. notification_outbox_mark() — no internal check. Could mark an arbitrary
--    outbox row 'sent', which SUPPRESSES the real message while the record claims
--    it was delivered. Silent notification loss for a guessable id.
--
-- 3. dispatch_notification() — no internal check. Could be used to make the
--    platform re-dispatch outbox rows on demand (notification spam).
--
-- 4. get_invoice_for_job(p_job_id) — no internal check, and it is a SECURITY
--    DEFINER reader. Any caller could pass any job id and read that job's invoice:
--    amounts, customer id, payment state. Fixed by checking that the caller is
--    party to the job.
--
-- 5. get_customer_jobs(p_customer_id) — PRE-EXISTING, not from this work. Takes
--    the customer id AS A PARAMETER, sets `row_security = off`, and returns the
--    matching jobs with no check that the caller is that customer. Anyone —
--    signed in or not — could enumerate any customer's jobs including their
--    prices. Fixed the same way.
--
-- 6. next_invoice_number() — no check. Only bumps a sequence, so low impact, but
--    it is server-side bookkeeping and has no business being world-callable.
--
-- Deliberately NOT changed: get_pricing_rules() and get_cms_settings() have no
-- internal check either, but the estimator runs before login by design, so those
-- are public content and must stay readable.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Revoke EXECUTE from the client roles ──────────────────────────────────
-- notify(): triggers only, which run as the table owner and need no grant.
REVOKE EXECUTE ON FUNCTION public.notify(TEXT, TEXT, TEXT, UUID, TEXT, JSONB, UUID)
  FROM anon, authenticated;

-- Outbox outcome recording: the transport function (service_role) only.
REVOKE EXECUTE ON FUNCTION public.notification_outbox_mark(UUID, TEXT, TEXT, TEXT)
  FROM anon, authenticated;

-- Dispatch: admin-driven from the app, so `authenticated` keeps it and the
-- function's own is_master_admin() check decides. No API role needs anon.
REVOKE EXECUTE ON FUNCTION public.dispatch_notification(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.dispatch_pending_notifications(INTEGER) FROM anon;

-- Sequence bookkeeping: no client role.
REVOKE EXECUTE ON FUNCTION public.next_invoice_number() FROM anon, authenticated;

-- Re-assert the grants we intend, so a future default-privilege change cannot
-- silently reopen these.
GRANT EXECUTE ON FUNCTION public.dispatch_notification(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_pending_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notification_outbox_mark(UUID, TEXT, TEXT, TEXT) TO service_role;

-- ─── 2. get_invoice_for_job: authorise before reading ─────────────────────────
-- Same signature and same output shape as before, so existing callers are
-- unaffected; the only change is that an unrelated caller now gets an error
-- instead of another customer's invoice.
CREATE OR REPLACE FUNCTION public.get_invoice_for_job(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job RECORD;
BEGIN
  SELECT id, customer_id, partner_id INTO v_job
    FROM public.repair_jobs WHERE id = p_job_id;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Party to the job: its customer, a member of its workshop, or a platform admin.
  IF NOT (
    public.is_master_admin()
    OR v_job.customer_id = auth.uid()
    OR (v_job.partner_id IS NOT NULL
        AND public.has_partner_membership(v_job.partner_id,
              ARRAY['owner','mechanic','staff']::membership_role[]))
  ) THEN
    -- Same code `advance_job_status` uses for an unauthorised caller, so the app
    -- surfaces it as a permission problem rather than an empty invoice.
    RAISE EXCEPTION 'not authorised to read this invoice' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb)
      FROM (
        SELECT i.id, i.invoice_number, i.status, i.initial_estimation_cost,
               i.final_cost, i.currency, i.line_items, i.created_at,
               i.released_at, i.expires_at, i.paid_at, i.decline_reason,
               i.payment_method,
               CASE WHEN i.initial_estimation_cost IS NULL THEN NULL
                    ELSE i.final_cost - i.initial_estimation_cost END AS delta,
               (SELECT jsonb_build_object('submitted_at', e.created_at, 'note', e.note,
                                          'panels', e.panels)
                  FROM public.partner_final_estimations e
                 WHERE e.job_id = i.job_id AND e.status = 'submitted'
                 LIMIT 1) AS final_estimation
          FROM public.invoices i
         WHERE i.job_id = p_job_id
      ) x
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_invoice_for_job(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_invoice_for_job(UUID) TO authenticated;

-- ─── 3. get_customer_jobs: authorise before reading ──────────────────────────
-- The parameter is kept (existing callers pass it) but is no longer trusted: a
-- caller may only ask for their own jobs unless they are a platform admin.
CREATE OR REPLACE FUNCTION public.get_customer_jobs(p_customer_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE result json;
BEGIN
  -- Was: any caller could pass any customer id and read their jobs, because this
  -- function runs with row security off. The id is now checked against the
  -- caller's own session.
  IF auth.uid() IS DISTINCT FROM p_customer_id AND NOT public.is_master_admin() THEN
    RAISE EXCEPTION 'not authorised to read another customer''s jobs'
      USING ERRCODE = '42501';
  END IF;

  SET LOCAL row_security = off;
  SELECT json_agg(row_to_json(sub) ORDER BY sub.created_at DESC) INTO result
  FROM (
    SELECT rj.id, rj.status, rj.created_at,
           rj.final_cost, rj.initial_estimation_cost,
           v.make, v.model, v.license_plate,
           pt.shop_name AS partner_name
    FROM repair_jobs rj
    LEFT JOIN vehicles v ON v.id = rj.vehicle_id
    LEFT JOIN partners pt ON pt.id = rj.partner_id
    WHERE rj.customer_id = p_customer_id
  ) sub;
  RETURN COALESCE(result, '[]'::json);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_customer_jobs(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_customer_jobs(uuid) TO authenticated;

-- ─── 4. Verification ─────────────────────────────────────────────────────────
WITH checks(ord, chk, got, want) AS (
  SELECT 1, 'anon cannot execute notify()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='notify'
        AND grantee IN ('anon','authenticated')), '0'
  UNION ALL SELECT 2, 'anon cannot execute notification_outbox_mark()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='notification_outbox_mark'
        AND grantee IN ('anon','authenticated')), '0'
  UNION ALL SELECT 3, 'anon cannot execute dispatch_notification()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='dispatch_notification'
        AND grantee='anon'), '0'
  UNION ALL SELECT 4, 'anon cannot execute get_invoice_for_job()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='get_invoice_for_job'
        AND grantee='anon'), '0'
  UNION ALL SELECT 5, 'anon cannot execute get_customer_jobs()',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='get_customer_jobs'
        AND grantee='anon'), '0'
  UNION ALL SELECT 6, 'service_role KEEPS notification_outbox_mark() (transport/drain)',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='notification_outbox_mark'
        AND grantee='service_role'), '1'
  UNION ALL SELECT 7, 'authenticated keeps dispatch_notification() (admin UI)',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND routine_name='dispatch_notification'
        AND grantee='authenticated'), '1'
  UNION ALL SELECT 8, 'get_invoice_for_job now checks the caller',
    (SELECT (pg_get_functiondef(p.oid) LIKE '%not authorised to read this invoice%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.proname='get_invoice_for_job'), 'true'
  UNION ALL SELECT 9, 'get_customer_jobs now checks the caller',
    (SELECT (pg_get_functiondef(p.oid) LIKE '%not authorised to read another customer%')::text
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.proname='get_customer_jobs'), 'true'
  UNION ALL SELECT 10, 'public pricing/CMS settings still readable by anon',
    (SELECT count(*)::text FROM information_schema.routine_privileges
      WHERE routine_schema='public' AND grantee='anon'
        AND routine_name IN ('get_pricing_rules','get_cms_settings')), '2'
)
SELECT CASE WHEN got = want THEN 'PASS' ELSE '*** FAIL ***' END AS result, chk, got, want
FROM checks ORDER BY ord;
