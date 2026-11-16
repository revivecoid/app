-- The bank account could never be shown or set.
--
-- payment_config has RLS switched on but no policy at all, so:
--   * a customer reading the invoice page could never see which methods were
--     on or which account to transfer to — the screen always fell back to
--     "rekening tujuan belum dikonfigurasi", and
--   * no admin could write a bank account either, because every write was
--     rejected by the same missing policy.
--
-- The table holds one row (id = 1): which payment methods are on, and the
-- destination accounts for manual transfer.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_config'
      AND policyname = 'Signed in customers can read payment config'
  ) THEN
    CREATE POLICY "Signed in customers can read payment config"
      ON public.payment_config
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_config'
      AND policyname = 'Admins can update payment config'
  ) THEN
    CREATE POLICY "Admins can update payment config"
      ON public.payment_config
      FOR UPDATE
      TO authenticated
      USING (public.is_master_admin())
      WITH CHECK (public.is_master_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payment_config'
      AND policyname = 'Admins can insert payment config'
  ) THEN
    CREATE POLICY "Admins can insert payment config"
      ON public.payment_config
      FOR INSERT
      TO authenticated
      WITH CHECK (public.is_master_admin());
  END IF;
END;
$$;
