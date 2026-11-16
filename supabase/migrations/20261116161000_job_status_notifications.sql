-- Job status notifications were unwritable, so no job could change status.
--
-- enqueue_job_notification still inserted into notification_outbox without
-- channel or to_address, both NOT NULL since the multi-channel rewrite. Every
-- call raised 23502, which means transition_job — and therefore settle_payment,
-- admin_review_payment, and every stage advance — aborted. The fix routes the
-- job event through public.notify(), which is the single place that resolves
-- recipients, honours notification_preferences, applies the provider routing and
-- writes one row per reachable channel.

-- One label map, used by every notification body and available to the client.
CREATE OR REPLACE FUNCTION public.job_status_label(p_status text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_status
    WHEN '2_estimated'         THEN 'Estimasi Selesai'
    WHEN '3_booked'            THEN 'Dijadwalkan'
    WHEN '5_admitted'          THEN 'Kendaraan Masuk'
    WHEN '3_inspected'         THEN 'Inspeksi Selesai'
    WHEN '4_paid'              THEN 'Pembayaran Dikonfirmasi'
    WHEN '6_in_progress'       THEN 'Dalam Pengerjaan'
    WHEN '7_finished'          THEN 'Selesai Dikerjakan'
    WHEN '8_awaiting_delivery' THEN 'Menunggu Pengantaran'
    WHEN '9_done'              THEN 'Selesai'
    WHEN '0_cancelled'         THEN 'Dibatalkan'
    ELSE COALESCE(p_status, 'Status pesanan')
  END;
$function$;

CREATE OR REPLACE FUNCTION public.enqueue_job_notification(
  p_job_id uuid,
  p_recipient uuid,
  p_event text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_job  public.repair_jobs;
  v_body text;
BEGIN
  IF p_job_id IS NULL THEN RETURN; END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  IF NOT FOUND OR v_job.customer_id IS NULL THEN RETURN; END IF;

  v_body := CASE p_event
    WHEN '2_estimated' THEN
      'Estimasi Anda sudah selesai. Pilih jadwal dan bengkel untuk melanjutkan.'
    WHEN '3_booked' THEN
      format('Kendaraan Anda dijadwalkan masuk%s. Bengkel akan menghubungi Anda sebelum hari-H.',
             COALESCE(' pada ' || to_char(v_job.scheduled_date, 'DD Mon YYYY'), ''))
    WHEN '5_admitted' THEN
      'Kendaraan Anda sudah diterima di bengkel dan menunggu inspeksi.'
    WHEN '3_inspected' THEN
      'Inspeksi selesai. Invoice perbaikan sudah tersedia di aplikasi untuk Anda tinjau.'
    WHEN '4_paid' THEN
      'Pembayaran Anda sudah kami terima. Pengerjaan akan segera dimulai.'
    WHEN '6_in_progress' THEN
      'Kendaraan Anda sedang dikerjakan oleh bengkel.'
    WHEN '7_finished' THEN
      'Pengerjaan selesai. Kami akan mengabari untuk pengantaran kendaraan.'
    WHEN '8_awaiting_delivery' THEN
      'Kendaraan Anda siap diantar. Mohon konfirmasi jadwal pengantaran di aplikasi.'
    WHEN '9_done' THEN
      'Kendaraan Anda sudah selesai dan diserahkan. Terima kasih telah menggunakan re-V.'
    WHEN '0_cancelled' THEN
      'Pesanan Anda dibatalkan. Hubungi kami bila ini tidak sesuai.'
    ELSE
      format('Status pesanan Anda sekarang: %s.', public.job_status_label(p_event))
  END;

  -- notify() resolves the customer, the channels, the addresses and the
  -- provider, and writes a valid notification_outbox row per channel.
  PERFORM public.notify(
    p_event,
    public.job_status_label(p_event),
    v_body,
    p_job_id,
    'customer',
    p_payload);
END;
$function$;
