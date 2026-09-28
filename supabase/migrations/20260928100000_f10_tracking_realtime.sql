-- =============================================================================
-- 20260928100000_f10_tracking_realtime.sql
-- Fase 10: publikasi realtime untuk tabel live UI
-- Mengatasi: C-43
-- =============================================================================

-- Tambahkan tabel ke publikasi realtime (idempoten)
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['repair_jobs','repair_photos','notifications','payments','job_milestones'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      RAISE NOTICE 'Added % to supabase_realtime', t;
    ELSE
      RAISE NOTICE '% already in supabase_realtime', t;
    END IF;
  END LOOP;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'supabase_realtime publication not found — skip (local dev)';
END;
$$;

-- Verifikasi
SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('repair_jobs','repair_photos','notifications','payments','job_milestones','partner_messages')
ORDER BY tablename;
