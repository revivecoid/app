-- =============================================================================
-- 20260928050000_add_commission_and_valet_settings.sql
-- Tambah commission_rate ke partners, valet_fee ke app_settings
-- Idempoten
-- =============================================================================

-- commission_rate column
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS commission_rate numeric(5,4) NOT NULL DEFAULT 0.10
  CHECK (commission_rate >= 0 AND commission_rate <= 1);

-- RPC: admin set commission rate
CREATE OR REPLACE FUNCTION public.admin_set_commission_rate(
  p_partner_id uuid,
  p_rate       numeric
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only admins can set commission rates';
  END IF;
  IF p_rate < 0 OR p_rate > 1 THEN
    RAISE EXCEPTION 'Commission rate must be between 0 and 1 (e.g. 0.10 = 10%%)';
  END IF;
  UPDATE public.partners SET commission_rate = p_rate, updated_at = now()
   WHERE id = p_partner_id;
  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('SET_COMMISSION_RATE', 'partners', p_partner_id, auth.uid(),
    jsonb_build_object('rate', p_rate));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_set_commission_rate(uuid, numeric) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_commission_rate(uuid, numeric) TO authenticated;

-- RPC: admin set valet fee (global)
CREATE OR REPLACE FUNCTION public.admin_set_valet_fee(p_fee bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only admins can set valet fee';
  END IF;
  IF p_fee < 0 THEN RAISE EXCEPTION 'Valet fee cannot be negative'; END IF;
  INSERT INTO public.app_settings (key, value)
  VALUES ('valet_fee_base', p_fee::text::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = p_fee::text::jsonb;
  INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
  VALUES ('SET_VALET_FEE', 'app_settings',
    '00000000-0000-0000-0000-000000000000'::uuid, auth.uid(),
    jsonb_build_object('fee', p_fee));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_set_valet_fee(bigint) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_set_valet_fee(bigint) TO authenticated;

-- Update partner_settlements view to use real commission_rate
DROP VIEW IF EXISTS public.partner_settlements;
CREATE VIEW public.partner_settlements AS
  SELECT p.id AS partner_id, p.shop_name,
    date_trunc('day', py.paid_at) AS settlement_date,
    count(py.id)      AS payment_count,
    sum(py.amount)    AS gross_amount,
    sum(round(py.amount * p.commission_rate))::bigint AS commission,
    sum(py.amount - round(py.amount * p.commission_rate))::bigint AS net_payout
  FROM public.payments py
  JOIN public.repair_jobs j ON j.id = py.job_id
  JOIN public.partners p    ON p.id = j.partner_id
  WHERE py.status = 'paid'
  GROUP BY p.id, p.shop_name, date_trunc('day', py.paid_at);
GRANT SELECT ON public.partner_settlements TO authenticated;

-- Verify
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partners' AND column_name = 'commission_rate';
