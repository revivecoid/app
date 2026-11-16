# Estimator learning loop

The estimator improves **without training a model**. Two pieces ship today:

1. few-shot context injected into the prompt at inference time;
2. automatic capture of every invoiced job as a labelled training pair.

Both live outside the model, so they work with whichever provider the
`ai_config` cascade picks (9Router, Gemini, Groq, OpenAI-compatible).

## 1. Few-shot context (live)

`supabase/functions/_shared/training_context.ts` — pure scoring/formatting,
unit-tested with `deno test supabase/functions/_shared/`.

Source rows:

| source | filter | used for |
|---|---|---|
| `ai_training_context` | `is_active_context = true` | real workshop cases: car, damage description, actual invoice total |
| `ai_learning_panel_reviews` | `verdict = false` | panel severities the reviewer rejected, shown as "do not repeat this mistake" |

Behaviour:

- Ranking: brand/model word hit weighs 3, body hit weighs 1, newest first on a tie
  (`normaliseTerms` keeps 2-letter tokens so `RH`/`LH` still distinguish sides).
- Caps: up to 5 cases, 700 chars per case, up to 5 corrections, 3,000 chars total
  (≈ 850 prompt tokens — roughly +8–25% input tokens per estimate).
- The block is prefixed to the master prompt and explicitly framed as *data, not
  instructions*, so a case body cannot hijack the model.
- Any failure loading context is swallowed with a warning: an estimate must never
  fail because the context table is unreachable.

Provenance returned in `structuredData`:

```json
"training_context": { "cases": 1, "corrections": 0, "case_ids": ["6d4960a4-…"] },
"source_photos": { "keys": ["<uid>/estimator/1794795771119_x.jpg"], "count": 1 }
```

`source_photos.keys` are durable R2 keys derived from the presigned URLs the model
was given (the signed URLs themselves expire in minutes).

## 2. Dataset capture (live)

Migration `20261116000000_ai_estimation_dataset.sql`.

`public.ai_estimation_dataset` gets one row per job that reaches a real invoice,
inserted by the trigger `capture_estimation_dataset_trg` on `repair_jobs`
(`AFTER INSERT OR UPDATE … WHEN final_cost > 0`).

| column | content |
|---|---|
| `job_id` | unique, one row per job (upserted on later updates) |
| `photo_keys` | `estimation_result → source_photos → keys` |
| `structured_data` | the estimator's full output (`assessment` + `financial_estimation`) |
| `car_make_model` | from `vehicles` (`make model year`) |
| `initial_estimation_cost` / `final_cost` | estimate vs actual invoice |
| `is_training_ready` | `final_cost > 0` **and** at least one photo key |
| `promoted_case_id` | set once a human promotes the row into `ai_training_context` |

RLS: only `public.is_master_admin()` may select. No insert/update policy — writes
come from the `SECURITY DEFINER` trigger and the service role.

### Promotion is manual, on purpose

A captured job is **not** auto-injected into the prompt. Auto-promotion would let a
single bad estimate poison every later estimate. Promote reviewed cases:

```sql
INSERT INTO public.ai_training_context
  (car_make_model, damage_description, resolved_actual_cost, is_active_context)
SELECT
  d.car_make_model,
  'Kasus ' || d.status || '. ' || COALESCE(
    (SELECT string_agg(
        p ->> 'panel_name' || ' (' || (p ->> 'panel_severity') || ', ganti: ' || (p ->> 'requires_replacement') || ')',
        '; ')
     FROM jsonb_array_elements(d.structured_data -> 'assessment' -> 'damaged_panels_detail') p),
    'tanpa detail panel') || '. Biaya riil: Rp' || to_char(d.final_cost, 'FM999G999G999'),
  4750000,
  true
FROM public.ai_estimation_dataset d
WHERE d.is_training_ready
  AND d.promoted_case_id IS NULL
  AND d.final_cost > 0;

-- then link them back
UPDATE public.ai_estimation_dataset d
   SET promoted_case_id = c.id
  FROM public.ai_training_context c
 WHERE d.promoted_case_id IS NULL
   AND c.created_at > NOW() - INTERVAL '1 minute';
```

(Adjust the last step to whatever key you trust; the link is bookkeeping, not
correctness-critical.)

## 3. Sizing — what each path needs

Per-estimate token cost, computed from the deployed prompt (4,166 chars) plus one
photo and the JSON reply:

| part | tokens |
|---|---|
| master prompt | ~1,150 |
| one photo | ~1,000–1,600 |
| JSON output | ~1,500–2,500 |
| **total** | **~2,500–2,800 in / ~1,500–2,500 out** |
| + 3 few-shot cases | +~250 input |
| + 10 cases (at the cap) | +~850 input |

Training paths:

| path | examples | tokens | notes |
|---|---|---|---|
| few-shot (shipped) | 3–10 good cases | 0 training tokens | grows with every promotion |
| managed fine-tune | dozens to start; ~1,000–5,000 for a domain vision adapter | ~2.5M–22M per epoch, 2–3 epochs | dataset leaves the infra, weights stay vendor-side, no offline |
| self-host LoRA | 100–500 for a behaviour shift | same volume, billed as GPU-hours | needs a ≥24 GB VRAM box; `e2-small` cannot serve a VLM |

Traffic that matters is **invoiced jobs**, not vendor calls: 5 estimates/day →
150/month → 1,000 labelled pairs in ~7 months; 20/day → ~2 months.

## 4. Verification

```bash
deno test supabase/functions/_shared/
deno check supabase/functions/vision-estimation/index.ts
deno lint supabase/functions/vision-estimation/index.ts supabase/functions/_shared/*.ts
```

Live check: a real estimate returns `training_context.cases >= 1` and a non-empty
`source_photos.keys`, and `ai_usage` records the call.
