-- A workshop's schedule could never be saved.
--
-- partner_update_capacity had two defects that both abort the write before any
-- row lands:
--   1. `to_jsonb(p_working_days)` / `to_jsonb(p_blacklisted_dates)` are jsonb,
--      while partner_schedules.standard_working_days is integer[] and
--      blacklisted_dates is date[]. Postgres raises 42804 (datatype mismatch).
--   2. the ON CONFLICT branch sets `updated_at = now()`, but partner_schedules
--      has no updated_at column. 42703.
-- partner_schedules had zero rows, so "Simpan" always reported an error and the
-- owner's working days / slots per day were never stored.
--
-- The function now writes the arrays directly, and updated_at is added so the
-- conflict branch is valid.

ALTER TABLE public.partner_schedules
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE OR REPLACE FUNCTION public.partner_update_capacity(
  p_working_days integer[],
  p_slots_per_day integer,
  p_blacklisted_dates date[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_partner_id uuid;
BEGIN
  v_partner_id := get_my_partner_id();
  IF v_partner_id IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED: Not a partner'; END IF;
  IF NOT has_partner_membership(v_partner_id, ARRAY['owner']::public.membership_role[]) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only owner can update capacity settings';
  END IF;
  IF p_slots_per_day IS NULL OR p_slots_per_day < 1 OR p_slots_per_day > 50 THEN
    RAISE EXCEPTION 'VALIDATION: slots_per_day must be 1-50, got %', p_slots_per_day;
  END IF;

  INSERT INTO public.partner_schedules
    (partner_id, guaranteed_slots_per_day, standard_working_days, blacklisted_dates, updated_at)
  VALUES
    (v_partner_id,
     p_slots_per_day,
     COALESCE(p_working_days, ARRAY[1,2,3,4,5,6]::integer[]),
     COALESCE(p_blacklisted_dates, ARRAY[]::date[]),
     now())
  ON CONFLICT (partner_id) DO UPDATE
    SET guaranteed_slots_per_day = EXCLUDED.guaranteed_slots_per_day,
        standard_working_days    = EXCLUDED.standard_working_days,
        blacklisted_dates        = EXCLUDED.blacklisted_dates,
        updated_at               = now();
END;
$function$;

-- The capacity read must not fail on an empty table either: a partner with no
-- row yet should get the defaults, not null.
CREATE OR REPLACE FUNCTION public.partner_get_capacity()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_partner_id uuid; v_row public.partner_schedules;
BEGIN
  v_partner_id := get_my_partner_id();
  IF v_partner_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'UNAUTHORIZED: Not a partner');
  END IF;

  SELECT * INTO v_row FROM public.partner_schedules WHERE partner_id = v_partner_id;

  RETURN jsonb_build_object(
    'ok', true,
    'working_days', COALESCE(v_row.standard_working_days, ARRAY[1,2,3,4,5,6]::integer[]),
    'slots_per_day', COALESCE(v_row.guaranteed_slots_per_day, 5),
    'blacklisted_dates', COALESCE(v_row.blacklisted_dates, ARRAY[]::date[]),
    'has_row', v_row.partner_id IS NOT NULL
  );
END;
$function$;
