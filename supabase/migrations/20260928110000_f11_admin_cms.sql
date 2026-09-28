-- =============================================================================
-- 20260928110000_f11_admin_cms.sql
-- Fase 11: get_customer_jobs RPC, Ops Matrix search
-- Mengatasi: C-30
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: get_customer_jobs RPC (C-30)
-- Admin versi get_customer_jobs — cek is_master_admin()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_customer_jobs(p_customer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT is_master_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only master admins can view customer job history';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',            r.id,
      'status',        r.status,
      'created_at',    r.created_at,
      'scheduled_date',r.scheduled_date,
      'final_cost',    r.final_cost,
      'contact_phone', r.contact_phone,
      'service_area',  r.service_area,
      'vehicle', jsonb_build_object(
        'make',          v.make,
        'model',         v.model,
        'year',          v.year,
        'license_plate', v.license_plate
      ),
      'partner', CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id',        p.id,
        'shop_name', p.shop_name
      ) END
    ) ORDER BY r.created_at DESC
  ) INTO v_result
  FROM public.repair_jobs r
  LEFT JOIN public.vehicles v ON v.id = r.vehicle_id
  LEFT JOIN public.partners p ON p.id = r.partner_id
  WHERE r.customer_id = p_customer_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_customer_jobs(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_customer_jobs(uuid) TO authenticated;

-- Verifikasi
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname = 'get_customer_jobs';
