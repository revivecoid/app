# Estimator Repair Policy

Business rules applied by `supabase/functions/vision-estimation` **after** the vision
model answers, so they hold whichever model in the `ai_config` cascade replied. The
logic lives in `supabase/functions/_shared/repair_policy.ts` and is unit-tested by
`supabase/functions/_shared/repair_policy_test.ts`.

## Rule 1 — severe damage is replacement-only

A panel gets **no repair option** when either:

- `panel_severity = 'berat'` and the damage is deformation (`damage_type` `dent`), or
- the part is broken/cracked/punctured (`damage_type = 'broken'` or `broken_found > 0`).

A deep scratch with no deformation stays repairable (repaint), even at `berat`.

Enforced per panel by writing:

| field | value |
|---|---|
| `requires_replacement` | `true` |
| `repair_allowed` | `false` |
| `recommended_action` | `"replace"` |
| `action_reason` | Indonesian reason string shown in the app |

Otherwise `repair_allowed = true` and `recommended_action` is `"repair"` or `"replace"`
depending on what the model decided. The knobs are `REPLACE_ONLY_SEVERITIES` and
`REPLACE_ONLY_DAMAGE_TYPES` in `repair_policy.ts` — change them there, not in the prompt.

## Rule 2 — Quarter panel replacement drags welded panels into the job

Source: Om Popoy, workshop. Replacing a Quarter panel (LH or RH, **any car**) is welded
work: the quarter is welded to the **Side Roof**, the **Trisplang**, the **opening
bagasi**, and the **Inner Quarter**. Disassembly means cutting those welds, so the labour
is heavy, and every adjoining panel touched by the welds must be repainted.

Trigger: a panel named `Quarter RH` / `Quarter LH` with `requires_replacement = true`
(which Rule 1 now forces for severe quarter damage).

The estimator appends these items automatically — the model is told **not** to invent
them, so they are added once and named consistently:

| Item added | Why |
|---|---|
| `Bongkar Quarter <SIDE>` | cut welds on Side Roof, Trisplang, opening bagasi, Inner Quarter |
| `Las Quarter <SIDE>` | weld the new quarter back to those panels |
| `Cat Side Roof <SIDE>` | adjoining panel burned by welds — repaint |
| `Cat Trisplang <SIDE>` | adjoining panel burned by welds — repaint |
| `Cat Inner Quarter <SIDE>` | adjoining panel burned by welds — repaint |
| `Cat Opening Bagasi` | added once, even when both quarters are replaced |

Each derived item carries `derived: true`, `derived_from: "quarter_replacement"`,
`pricing_pending: true`, and `calculated_cost: 0` until it has a real price.
`assessment.total_panels_damaged` excludes derived lines.

## Prices are deliberately not set yet

Derived items are priced from `pricing_rules` like any other item, but the row is only
created when the workshop decides the number. Until then the item stays on the estimate
with `pricing_pending: true` and the app shows **"Harga menyusul"**; the subtotal
excludes it and `financial_estimation.pricing_pending_items` lists the names.

To set a price later, either:

1. **CMS → Pricing Rules → "Jasa Penggantian Quarter"** (section already wired in
   `lib/features/cms/presentation/pricing_rules_screen.dart`), or
2. SQL:

```sql
INSERT INTO pricing_rules (panel_id, panel_name, base_rate, severity_min, severity_max, mode, is_active)
VALUES ('LABOR_BONGKAR_QUARTER_RH', 'Bongkar Quarter RH', 450000, 1.0, 1.0, 'auto', true)
ON CONFLICT (panel_id) DO UPDATE SET base_rate = EXCLUDED.base_rate;
```

`panel_name` must match the derived item name **exactly** — that string is the join key.
Severity multipliers are ignored for derived lines (flat price), and a `base_rate` of `0`
is treated as "still pending", not as a free job.

## Response contract (new fields)

```json
"financial_estimation": {
  "repair_policy": {
    "replace_only_severities": ["berat"],
    "replace_only_damage_types": ["broken"],
    "replace_only_panels": ["Quarter RH"]
  },
  "quarter_replacement": {
    "applied": true,
    "sides": ["RH"],
    "labour_items": ["Bongkar Quarter RH", "..."],
    "note": "Penggantian panel quarter dilas menyatu dengan ..."
  },
  "pricing_pending_items": ["Bongkar Quarter RH", "..."]
}
```

Per panel: `repair_allowed`, `recommended_action` (`repair` | `replace` | `labor`),
`action_reason`, and on derived lines `derived`, `derived_from`, `quarter_side`,
`pricing_pending`, `note`.

## Verify

```bash
deno test supabase/functions/_shared/repair_policy_test.ts
deno check supabase/functions/vision-estimation/index.ts
deno lint supabase/functions/vision-estimation/index.ts
```
