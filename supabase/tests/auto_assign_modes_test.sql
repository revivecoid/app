-- =============================================================================
-- Verification harness for execute_auto_assign allocation modes.
-- Runs entirely inside a transaction that is ROLLED BACK, so nothing persists.
-- Test partners use priority 1/2/3 and capacity 5 unless a scenario overrides it.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE _res(label text, got uuid, want uuid, ok boolean) ON COMMIT DROP;

-- Keep only the fixtures in play.
UPDATE public.partners SET auto_assign_active = false;

INSERT INTO public.partners (id, shop_name, auto_assign_active, auto_assign_priority, auto_assign_capacity, is_active)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'T_A pri1', true, 1, 5, true),
  ('22222222-2222-2222-2222-222222222222', 'T_B pri2', true, 2, 5, true),
  ('33333333-3333-3333-3333-333333333333', 'T_C pri3', true, 3, 5, true);

-- Jobs: only status matters (3_booked counts as active).
INSERT INTO public.repair_jobs (id, customer_id, vehicle_id, status) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked'),
  ('aaaaaaaa-0000-0000-0000-000000000004', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked'),
  ('aaaaaaaa-0000-0000-0000-000000000005', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked'),
  ('aaaaaaaa-0000-0000-0000-000000000006', '205620af-bf7f-4192-9043-aa0c0f053999', '5c81c9dd-46fc-4088-8bfe-0a0a7d08bcf7', '3_booked');

UPDATE public.auto_assign_settings SET is_active = true, match_location = false WHERE id = 1;

-- ── S1: fill_first — P1 empty, last=P1 so rotation would hand the job to P2.
--        Expect P1: a higher priority workshop that is empty jumps the queue.
UPDATE public.auto_assign_settings SET mode = 'fill_first', last_partner_id = '11111111-1111-1111-1111-111111111111' WHERE id = 1;
INSERT INTO _res SELECT 'S1 fill_first: P1 empty, rotation->P2 => P1', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000001')->>'partner_id')::uuid, '11111111-1111-1111-1111-111111111111'::uuid, NULL;

-- ── S2: fill_first — P1 now holds 1 job, last=P1 so rotation = P2.
--        Expect P2: no over-filling while P1 is occupied.
UPDATE public.auto_assign_settings SET last_partner_id = '11111111-1111-1111-1111-111111111111' WHERE id = 1;
INSERT INTO _res SELECT 'S2 fill_first: P1 occupied, rotation->P2 => P2', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000002')->>'partner_id')::uuid, '22222222-2222-2222-2222-222222222222'::uuid, NULL;

-- ── S3: fill_first — P1 pinned to capacity (1/1). Expect P2.
UPDATE public.partners SET auto_assign_capacity = 1 WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE public.auto_assign_settings SET last_partner_id = '11111111-1111-1111-1111-111111111111' WHERE id = 1;
INSERT INTO _res SELECT 'S3 fill_first: P1 full => P2', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000003')->>'partner_id')::uuid, '22222222-2222-2222-2222-222222222222'::uuid, NULL;

-- ── S4: strict_priority — P1 occupied but has a free slot again. Expect P1.
UPDATE public.partners SET auto_assign_capacity = 5 WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE public.auto_assign_settings SET mode = 'strict_priority' WHERE id = 1;
INSERT INTO _res SELECT 'S4 strict_priority: P1 has slot => P1', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000004')->>'partner_id')::uuid, '11111111-1111-1111-1111-111111111111'::uuid, NULL;

-- ── S5: round_robin — last=P1. Expect P2 (no empty-slot override in this mode).
UPDATE public.auto_assign_settings SET mode = 'round_robin', last_partner_id = '11111111-1111-1111-1111-111111111111' WHERE id = 1;
INSERT INTO _res SELECT 'S5 round_robin: last=P1 => P2', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000005')->>'partner_id')::uuid, '22222222-2222-2222-2222-222222222222'::uuid, NULL;

-- ── S6: fill_first — everything at capacity. Expect no assignment.
UPDATE public.partners SET auto_assign_capacity = 0 WHERE id IN ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333');
UPDATE public.auto_assign_settings SET mode = 'fill_first' WHERE id = 1;
INSERT INTO _res SELECT 'S6 fill_first: all full => NULL', (public.execute_auto_assign('aaaaaaaa-0000-0000-0000-000000000006')->>'partner_id')::uuid, NULL, NULL;

UPDATE _res SET ok = (got IS NOT DISTINCT FROM want);

SELECT label, got, want, ok FROM _res ORDER BY label;

ROLLBACK;
