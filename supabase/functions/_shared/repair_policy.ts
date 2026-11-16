/**
 * Estimator repair policy — business rules applied deterministically after the
 * vision model answers, so they hold whichever model in the cascade replied.
 *
 * Rule 1 (replace-only): when damage is severe enough that straightening is not
 * economical, or the part is broken/cracked/punctured, the estimate carries only
 * the replacement option — no repair line.
 *
 * Rule 2 (quarter panel): replacing a Quarter panel (LH or RH, any car) is
 * welded work. The quarter is welded to the Side Roof, the Trisplang, the
 * luggage opening (opening bagasi) and the Inner Quarter, so disassembly is
 * heavy and every adjoining panel touched by the welds must be repainted. Those
 * labour and paint items are added automatically.
 *
 * Prices are deliberately NOT set here. Each derived item is emitted with
 * `pricing_pending: true` and cost 0 until a pricing_rules row exists under the
 * exact item name (see docs/estimator_repair_policy.md).
 */

export type Severity = "ringan" | "sedang" | "berat";

const VALID_SEVERITIES: string[] = ["ringan", "sedang", "berat"];

/** Severities that leave replacement as the only option. */
export const REPLACE_ONLY_SEVERITIES: string[] = ["berat"];

/** Damage types that can never be repaired (cracked / punctured / severed). */
export const REPLACE_ONLY_DAMAGE_TYPES: string[] = ["broken"];

/** Matches "Quarter RH" / "Quarter LH" (spacing and case tolerant). */
export const QUARTER_PANEL_PATTERN = /^quarter\s+(rh|lh)$/i;

/**
 * Operations that are labour, not panels: a "replacement" verdict on them is
 * meaningless ("replace the AC refill"), so Rule 1 leaves them as operations.
 */
export const LABOUR_OPERATION_NAMES: string[] = [
  "b/p kaca depan",
  "b/p radiator & ac pack",
  "isi freon ac",
];

export interface PolicySummary {
  /** Panels the policy forced to replacement-only. */
  replaceOnlyPanels: string[];
  /** Sides ("RH"/"LH") whose Quarter panel is being replaced. */
  quarterSides: string[];
  /** Derived labour/paint items appended for quarter replacement. */
  derivedItems: string[];
}

export function normaliseSeverity(raw: unknown): Severity {
  const value = String(raw ?? "").toLowerCase().trim();
  return VALID_SEVERITIES.includes(value) ? (value as Severity) : "berat";
}

function panelsOf(structuredData: any): any[] {
  const list = structuredData?.assessment?.damaged_panels_detail;
  return Array.isArray(list) ? list : [];
}

function isDerived(panel: any): boolean {
  return panel?.derived === true;
}

/**
 * Rule 1 — decide, per panel, whether repair is still an option.
 * Mutates each panel: repair_allowed, recommended_action, action_reason,
 * requires_replacement, panel_severity.
 */
export function applyRepairPolicy(structuredData: any): string[] {
  const replaceOnly: string[] = [];

  for (const panel of panelsOf(structuredData)) {
    if (!panel || typeof panel !== "object" || isDerived(panel)) continue;

    const name = String(panel.panel_name ?? "").trim();
    if (!name) continue;

    const severity = normaliseSeverity(panel.panel_severity);
    panel.panel_severity = severity;

    if (LABOUR_OPERATION_NAMES.includes(name.toLowerCase())) {
      panel.requires_replacement = false;
      panel.repair_allowed = true;
      panel.recommended_action = "labor";
      continue;
    }

    const damageType = String(panel.damage_type ?? "").toLowerCase().trim();
    const broken = REPLACE_ONLY_DAMAGE_TYPES.includes(damageType) ||
      Number(panel.broken_found ?? 0) > 0;
    // A deep scratch on an otherwise sound panel is still repaint work, so
    // severity alone only blocks repair for deformation-type damage.
    const severityBlocksRepair = REPLACE_ONLY_SEVERITIES.includes(severity) &&
      damageType !== "scratch";

    if (broken || severityBlocksRepair) {
      panel.requires_replacement = true;
      panel.repair_allowed = false;
      panel.recommended_action = "replace";
      panel.action_reason = broken
        ? "Komponen pecah/patah — tidak dapat diperbaiki, hanya penggantian."
        : "Kerusakan berat — perbaikan (ketok/las tarik) tidak ekonomis, hanya penggantian panel.";
      replaceOnly.push(name);
      continue;
    }

    panel.repair_allowed = true;
    panel.recommended_action = panel.requires_replacement === true ? "replace" : "repair";
  }

  return replaceOnly;
}

interface QuarterItem {
  name: string;
  note: string;
  side: string;
}

function quarterLabourItems(side: string): QuarterItem[] {
  return [
    {
      name: `Bongkar Quarter ${side}`,
      note:
        "Pembongkaran panel quarter: potong las pada Side Roof, Trisplang, opening bagasi, dan Inner Quarter.",
      side,
    },
    {
      name: `Las Quarter ${side}`,
      note:
        "Pengelasan panel quarter baru ke Side Roof, Trisplang, opening bagasi, dan Inner Quarter.",
      side,
    },
    {
      name: `Cat Side Roof ${side}`,
      note: "Side Roof tertimpa las — wajib masuk jasa pengecatan.",
      side,
    },
    {
      name: `Cat Trisplang ${side}`,
      note: "Trisplang tertimpa las — wajib masuk jasa pengecatan.",
      side,
    },
    {
      name: `Cat Inner Quarter ${side}`,
      note: "Inner Quarter tertimpa las — wajib masuk jasa pengecatan.",
      side,
    },
  ];
}

/**
 * Rule 2 — a Quarter replacement drags welded adjoining panels into the job.
 * Mutates structuredData: appends derived items, flags the quarter panel.
 */
export function applyQuarterReplacementPolicy(structuredData: any): string[] {
  const panels = panelsOf(structuredData);
  const added: string[] = [];
  const sides = new Set<string>();

  for (const panel of panels) {
    if (!panel || typeof panel !== "object" || isDerived(panel)) continue;

    const name = String(panel.panel_name ?? "").trim();
    const match = name.match(QUARTER_PANEL_PATTERN);
    if (!match) continue;
    if (panel.requires_replacement !== true) continue;

    const side = match[1].toUpperCase();
    sides.add(side);
    panel.quarter_replacement = true;
    panel.quarter_side = side;
    panel.action_reason = panel.action_reason ??
      "Penggantian panel quarter — pembongkaran dan pengelasan menyatu dengan Side Roof, Trisplang, opening bagasi, dan Inner Quarter.";
  }

  if (sides.size === 0) return added;

  const existing = new Set(
    panels.map((p) => String(p?.panel_name ?? "").trim().toLowerCase()),
  );

  const orderedSides = [...sides].sort();
  const items: QuarterItem[] = [];
  for (const side of orderedSides) items.push(...quarterLabourItems(side));
  // Opening bagasi spans the rear and is one panel, so it is added once even
  // when both quarters are replaced.
  items.push({
    name: "Cat Opening Bagasi",
    note: "Opening bagasi tertimpa las — wajib masuk jasa pengecatan.",
    side: orderedSides.join("+"),
  });

  for (const item of items) {
    const key = item.name.trim().toLowerCase();
    if (existing.has(key)) continue;
    existing.add(key);

    panels.push({
      panel_name: item.name,
      panel_severity: "sedang",
      damage_type: "labor",
      scratches_found: 0,
      dents_found: 0,
      broken_found: 0,
      requires_replacement: false,
      repair_allowed: false,
      recommended_action: "labor",
      derived: true,
      derived_from: "quarter_replacement",
      quarter_side: item.side,
      note: item.note,
      pricing_pending: true,
      calculated_cost: 0,
    });
    added.push(item.name);
  }

  const damagedPanels = panels.filter((p) => !isDerived(p)).length;
  structuredData.assessment.total_panels_damaged = damagedPanels;

  return added;
}

/** Runs both rules in order: repair policy first, then quarter consequences. */
export function applyEstimatorPolicies(structuredData: any): PolicySummary {
  const replaceOnlyPanels = applyRepairPolicy(structuredData);
  const derivedItems = applyQuarterReplacementPolicy(structuredData);
  const quarterSides = [
    ...new Set(
      panelsOf(structuredData)
        .filter((p) => p?.quarter_replacement === true)
        .map((p) => String(p.quarter_side ?? "").toUpperCase())
        .filter((s) => s === "RH" || s === "LH"),
    ),
  ].sort();

  return { replaceOnlyPanels, quarterSides, derivedItems };
}
