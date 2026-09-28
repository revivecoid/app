-- =============================================================================
-- 20260928060000_f6_status_clients.sql
-- Fase 6: konstanta status, get_job_actions, job_stage_durations, realtime
-- Mengatasi: C-11, C-12, C-29, C-51, C-82, BIZ-09, BIZ-10, L-12, S-08
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 1: get_job_actions — aksi yang tersedia untuk pemanggil (C-48)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_job_actions(p_job_id uuid)
RETURNS TABLE (to_status text, label_id text, label_en text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job        public.repair_jobs;
  v_actor      text;
  v_partner_id uuid;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_partner_id := get_my_partner_id();

  IF is_master_admin() THEN
    v_actor := 'master_admin';
  ELSIF v_partner_id IS NOT NULL AND v_job.partner_id = v_partner_id THEN
    IF has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
      v_actor := 'owner';
    ELSIF has_partner_membership(v_partner_id, ARRAY['mechanic']::public.membership_role[]) THEN
      v_actor := 'mechanic';
    ELSIF has_partner_membership(v_partner_id, ARRAY['driver']::public.membership_role[]) THEN
      v_actor := 'driver';
    ELSE
      v_actor := 'staff';
    END IF;
  ELSIF v_job.customer_id = auth.uid() THEN
    v_actor := 'customer';
  ELSE
    RETURN;
  END IF;

  RETURN QUERY
    SELECT t.to_status, js.label_id, js.label_en
    FROM public.job_status_transitions t
    JOIN public.job_statuses js ON js.code = t.to_status
    WHERE t.from_status = v_job.status
      AND t.actor = v_actor
    ORDER BY js.sort_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_job_actions(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_job_actions(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 2: job_stage_durations view (BIZ-09, BIZ-10)
-- Hitung durasi per tahap dari job_status_history
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.job_stage_durations;
CREATE VIEW public.job_stage_durations AS
  SELECT
    h.job_id,
    h.from_status,
    h.to_status,
    h.created_at                           AS transitioned_at,
    lead(h.created_at) OVER w              AS next_transition_at,
    extract(epoch FROM
      lead(h.created_at) OVER w - h.created_at
    ) / 60.0                               AS duration_minutes
  FROM public.job_status_history h
  WINDOW w AS (PARTITION BY h.job_id ORDER BY h.created_at);

GRANT SELECT ON public.job_stage_durations TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 3: Tambah repair_jobs ke publikasi realtime (C-51)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- Tambah repair_jobs ke publikasi realtime bila belum ada
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'repair_jobs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.repair_jobs;
  END IF;
EXCEPTION WHEN others THEN
  -- Publikasi mungkin tidak ada di lokal — lanjut
  NULL;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BAGIAN 4: Verifikasi
-- ─────────────────────────────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--   AND proname = 'get_job_actions';
-- SELECT count(*) FROM public.job_stage_durations;  -- 0 bila belum ada history
