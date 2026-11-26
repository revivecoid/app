-- =============================================================================
-- Body & Paint stage tracking — six named steps, photo optional
-- Date: 2026-11-26
--
-- Why
-- ---
-- The workshop floor already recorded eight milestones, but two things were
-- wrong for the business:
--
--   * The customer's six-step body & paint sequence (bongkar, ketok/las, dempul,
--     cat, poles, pasang) did not exist as such. `assembly` ("pasang") was not a
--     stage at all, so a finished car could never report that its parts went
--     back on, and the customer tracker showed one undifferentiated "Active
--     Body & Painting" step with no sub-progress.
--
--   * Every mid-repair stage demanded at least one photo. A real workshop does
--     not photograph every panel beating, and a stage that cannot be recorded
--     without a camera in hand is a stage that goes unrecorded — so the customer
--     saw less, not more. Progress photos become OPTIONAL from
--     `disassembly` through `assembly`. Intake and QC keep their requirement:
--     those two are the evidence a dispute rests on (condition on arrival, and
--     the car as handed over).
--
-- What this migration does
-- ------------------------
--   1. `assembly` added to `ops_stage_roles` (UI + RLS gate agree).
--   2. `guard_repair_finished_needs_photo` accepts a completed body & paint
--      milestone as evidence of work, not only a `repair_photos` row. Without
--      this, making progress photos optional would leave `7_finished`
--      unreachable for a workshop that marked all six stages but uploaded
--      nothing — the guard would demand a photo the UI no longer asks for.
--   3. `transition_job` gets the same acceptance. It carries its own copy of the
--      rule; the two must agree or the button and the RPC disagree.
--   4. `job_milestones` and `job_milestone_photos` join the realtime
--      publication, so the customer tracker and the partner board update as the
--      floor marks steps instead of on the next full fetch.
--   5. `ops_complete_stage(p_job_id, p_stage_key, p_file_keys)` — one atomic
--      call for every mid-repair stage. The client previously wrote the
--      milestone and then asked for the status advance as two separate calls, so
--      a failure between them left the milestone recorded and the job behind it.
--      `p_file_keys` may be an empty array; that is the point.
--
-- 5_admitted's intake-photo rule is untouched on purpose: it guards the car's
-- condition on arrival, which is not "work in progress".
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. assembly ("pasang") — the sixth body & paint step
-- ---------------------------------------------------------------------------
INSERT INTO public.ops_stage_roles (stage_key, role) VALUES
  ('assembly', 'master_admin'),
  ('assembly', 'partner_mechanic'),
  ('assembly', 'partner_staff')
ON CONFLICT (stage_key, role) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Finishing needs evidence of work — a milestone counts, not only a photo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_repair_finished_needs_photo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contexts text[];
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- System moves (settlement, cron) are not a workshop claiming the work.
  IF current_setting('app.actor', true) = 'system' THEN
    RETURN NEW;
  END IF;

  -- An admin may move the job anyway, with a reason, and it is audited.
  IF public.is_master_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.status = '7_finished' THEN
    -- Proof that the work was done: either a progress photo, or a completed
    -- body & paint stage. Progress photos are optional by design, so the
    -- milestone has to be able to stand as the evidence on its own.
    IF EXISTS (
      SELECT 1 FROM public.repair_photos rp
       WHERE rp.job_id = NEW.id
         AND rp.step_context = ANY (ARRAY['in_progress', 'progress', 'finished', 'admitted'])
    ) THEN
      RETURN NEW;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.job_milestones m
       WHERE m.job_id = NEW.id
         AND m.status = 'completed'
         AND m.stage_key = ANY (ARRAY['disassembly', 'welding', 'body_filler',
                                      'painting', 'polishing', 'assembly'])
    ) THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION
      'PHOTO_REQUIRED: tandai minimal satu tahap pengerjaan atau unggah satu foto sebelum menandai pekerjaan selesai'
      USING ERRCODE = 'check_violation';

  ELSIF NEW.status = '5_admitted' THEN
    -- Proof of the car's condition when it arrived. The customer's own damage
    -- photos do not count: they were taken before the car reached the shop.
    -- Unchanged: an intake photo is still required.
    IF NOT EXISTS (
      SELECT 1 FROM public.repair_photos rp
       WHERE rp.job_id = NEW.id
         AND rp.step_context = ANY (ARRAY['booked', 'admitted', 'intake', 'vehicle_intake'])
    ) THEN
      RAISE EXCEPTION
        'PHOTO_REQUIRED: ambil foto kondisi kendaraan sebelum menerima kendaraan'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3. transition_job — same acceptance rule as the trigger above
--    Republished in full because plpgsql has no way to patch one branch. The
--    body is the live definition with only the 7_finished evidence test widened.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_job(
  p_job_id uuid,
  p_to text,
  p_expected_from text DEFAULT NULL::text,
  p_reason text DEFAULT NULL::text,
  p_meta jsonb DEFAULT '{}'::jsonb
)
RETURNS public.repair_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_job        public.repair_jobs;
  v_actor      text;
  v_partner_id uuid;
  v_allowed    boolean := false;
  v_is_system  boolean;
BEGIN
  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TRANSITION_ERROR: Job not found: %', p_job_id; END IF;

  IF p_expected_from IS NOT NULL AND v_job.status <> p_expected_from THEN
    RAISE EXCEPTION 'STALE_STATUS: Expected %, got %', p_expected_from, v_job.status;
  END IF;

  v_is_system  := (current_setting('app.actor', true) = 'system');
  v_partner_id := get_my_partner_id();

  IF v_is_system THEN
    v_actor := 'system';
  ELSIF is_master_admin() THEN
    v_actor := 'master_admin';
  ELSIF v_partner_id IS NOT NULL AND v_job.partner_id = v_partner_id THEN
    IF has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
      v_actor := 'owner';
    ELSIF has_partner_membership(v_partner_id, ARRAY['mechanic']::public.membership_role[]) THEN
      v_actor := 'mechanic';
    ELSIF has_partner_membership(v_partner_id, ARRAY['driver']::public.membership_role[]) THEN
      IF EXISTS (SELECT 1 FROM public.partners WHERE id = v_partner_id AND ops_view_mode = 'all_access') THEN
        v_actor := 'staff';
      ELSE
        v_actor := 'driver';
      END IF;
    ELSE
      v_actor := 'staff';
    END IF;
  ELSIF v_job.customer_id = auth.uid() THEN
    v_actor := 'customer';
  ELSE
    RAISE EXCEPTION 'TRANSITION_ERROR: Cannot determine actor for this job';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.job_status_transitions
    WHERE from_status = v_job.status AND to_status = p_to AND actor = v_actor
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: % → % not allowed for actor %', v_job.status, p_to, v_actor;
  END IF;

  IF v_actor = 'master_admin' AND p_reason IS NULL AND
     p_to NOT IN ('5_admitted','6_in_progress','7_finished','8_awaiting_delivery','9_done') THEN
    RAISE EXCEPTION 'TRANSITION_ERROR: Admin override requires a reason';
  END IF;

  -- Work must be evidenced before the job can be called finished. Either a
  -- progress photo or a completed body & paint stage counts: photos are optional
  -- by design, so the milestone alone has to satisfy this.
  IF p_to = '7_finished' AND v_actor IN ('owner','mechanic','staff') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.repair_photos rp
      WHERE rp.job_id = p_job_id
        AND rp.step_context IN ('in_progress','progress','finished')
    ) AND NOT EXISTS (
      SELECT 1
      FROM public.job_milestones m
      WHERE m.job_id = p_job_id
        AND m.status = 'completed'
        AND m.stage_key IN ('disassembly','welding','body_filler',
                            'painting','polishing','assembly')
    ) THEN
      RAISE EXCEPTION 'TRANSITION_ERROR: A progress photo or a completed repair stage is required before the job can be marked finished';
    END IF;
  END IF;

  IF p_to = '5_admitted' AND v_job.status = '3_booked' AND v_job.scheduled_date IS NOT NULL THEN
    INSERT INTO public.partner_booked_slots (partner_id, job_id, booked_date)
    VALUES (v_job.partner_id, p_job_id, v_job.scheduled_date::DATE) ON CONFLICT DO NOTHING;
  END IF;

  IF p_to IN ('9_done','0_cancelled') THEN
    UPDATE public.repair_jobs
       SET status = p_to, status_changed_at = now(), completed_at = now(), updated_at = now()
     WHERE id = p_job_id;
  ELSE
    UPDATE public.repair_jobs
       SET status = p_to, status_changed_at = now(), updated_at = now()
     WHERE id = p_job_id;
  END IF;

  IF v_job.customer_id IS NOT NULL THEN
    PERFORM enqueue_job_notification(p_job_id, v_job.customer_id, p_to,
      jsonb_build_object('from', v_job.status, 'actor', v_actor));
  END IF;

  INSERT INTO public.job_status_history
    (job_id, from_status, to_status, actor_user, actor_role, reason, meta)
  VALUES (p_job_id, v_job.status, p_to, auth.uid(), v_actor, p_reason, p_meta);

  IF v_actor = 'master_admin' THEN
    INSERT INTO public.admin_audit_log (action, target_type, target_id, performed_by, metadata)
    VALUES ('JOB_STATUS_TRANSITION','repair_jobs',p_job_id,auth.uid(),
      jsonb_build_object('from',v_job.status,'to',p_to,'reason',p_reason));
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id;
  RETURN v_job;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.transition_job(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.transition_job(uuid, text, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Realtime: the floor marks a step, the customer's tracker hears about it
--    Repair stages are two tables deep (`job_milestones` + photos), and neither
--    was published, so a customer watching the tracker saw nothing until the
--    whole job's status changed.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND tablename = 'job_milestones'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.job_milestones;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND tablename = 'job_milestone_photos'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.job_milestone_photos;
  END IF;
END $$;

-- Realtime still applies RLS, but REPLICA IDENTITY FULL is what lets a DELETE
-- payload carry the job_id the client filters on.
ALTER TABLE public.job_milestones REPLICA IDENTITY FULL;

-- ---------------------------------------------------------------------------
-- 5. ops_complete_stage — one atomic call, photos optional
--    p_file_keys may be '{}'. Empty is the normal case for the six body & paint
--    steps; intake and delivery keep their own RPCs and their photo rule.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.ops_complete_stage(uuid, text, text[]);

CREATE FUNCTION public.ops_complete_stage(
  p_job_id    uuid,
  p_stage_key text,
  p_file_keys text[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role         text;
  v_partner_id   uuid;
  v_job          record;
  v_stage        record;
  v_milestone    record;
  v_file_key     text;
  v_new_status   text;
  v_photo_count  int := 0;
BEGIN
  v_role       := (auth.jwt() -> 'app_metadata' ->> 'role')::text;
  v_partner_id := (auth.jwt() -> 'app_metadata' ->> 'partner_id')::uuid;

  IF v_role IS NULL OR v_role NOT IN ('partner_staff', 'partner_driver',
                                      'partner_mechanic', 'master_admin') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Unauthorized role: ' || coalesce(v_role, 'null'));
  END IF;

  -- Which stage, what status it triggers. The rules live in ops_stage_roles and
  -- kOpsStages in the app; this table is the server's copy of the same list.
  SELECT * INTO v_stage
    FROM (VALUES
      ('disassembly',  'Disassembly',            '6_in_progress'),
      ('welding',      'Welding / Panel Beating', NULL),
      ('body_filler',  'Body Filler',             NULL),
      ('painting',     'Painting',                NULL),
      ('polishing',    'Polishing & Detailing',   NULL),
      ('assembly',     'Reassembly',              NULL),
      ('qc_finished',  'Quality Control',         '7_finished')
    ) AS t(stage_key, label, advances_status)
   WHERE t.stage_key = p_stage_key;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Not a mid-repair stage: %s. Use ops_complete_intake or ops_complete_delivery.', p_stage_key));
  END IF;

  SELECT * INTO v_job FROM public.repair_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not found.');
  END IF;

  IF v_role <> 'master_admin' AND v_job.partner_id IS DISTINCT FROM v_partner_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Job not assigned to your workshop.');
  END IF;

  -- Repair may not be recorded before the customer has paid. Mirrors
  -- ops_may_act_on_stage(); checked here too because this function is
  -- SECURITY DEFINER and bypasses the policy that would otherwise enforce it.
  IF v_role <> 'master_admin'
     AND v_job.status NOT IN ('4_paid', '6_in_progress', '7_finished',
                              '8_awaiting_delivery', '9_done') THEN
    RETURN jsonb_build_object('success', false,
      'error', format('Repair work cannot be recorded from status: %s. Customer payment is required first.', v_job.status));
  END IF;

  -- The workshop's access mode. all_access lets any operator record any stage;
  -- the two restrictive modes defer to ops_stage_roles.
  IF v_role <> 'master_admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.partners p
       WHERE p.id = v_partner_id AND p.ops_view_mode = 'all_access'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.ops_stage_roles sr
       WHERE sr.stage_key = p_stage_key AND sr.role = v_role
    ) THEN
      RETURN jsonb_build_object('success', false,
        'error', format('Your role (%s) cannot complete stage %s at this workshop.', v_role, p_stage_key));
    END IF;
  END IF;

  INSERT INTO public.job_milestones
    (job_id, milestone_name, stage_key, status, completed_by, completed_at)
  VALUES (p_job_id, v_stage.label, p_stage_key, 'completed', auth.uid(), now())
  ON CONFLICT (job_id, stage_key) DO UPDATE
    SET status = 'completed', completed_by = auth.uid(), completed_at = now()
  RETURNING * INTO v_milestone;

  -- Photos are optional. An empty array is a valid submission, not a mistake.
  IF p_file_keys IS NOT NULL AND array_length(p_file_keys, 1) IS NOT NULL THEN
    FOREACH v_file_key IN ARRAY p_file_keys LOOP
      CONTINUE WHEN v_file_key IS NULL OR v_file_key = '';
      INSERT INTO public.job_milestone_photos
        (milestone_id, job_id, uploaded_by, file_key)
      VALUES (v_milestone.id, p_job_id, auth.uid(), v_file_key);
      v_photo_count := v_photo_count + 1;
    END LOOP;
  END IF;

  v_new_status := NULL;

  IF v_stage.advances_status IS NOT NULL AND v_job.status <> v_stage.advances_status THEN
    PERFORM public.transition_job(p_job_id, v_stage.advances_status, NULL, NULL, '{}');
    v_new_status := v_stage.advances_status;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'milestone_id', v_milestone.id,
    'stage_key', p_stage_key,
    'photos_saved', v_photo_count,
    'new_status', v_new_status
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ops_complete_stage(uuid, text, text[]) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ops_complete_stage(uuid, text, text[]) TO authenticated;
