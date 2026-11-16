import { assertEquals, assertExists } from "jsr:@std/assert@1";
import {
  applyEstimatorPolicies,
  applyQuarterReplacementPolicy,
  applyRepairPolicy,
  normaliseSeverity,
} from "./repair_policy.ts";

function payload(panels: any[]) {
  return {
    assessment: {
      severity_classification: "sedang",
      total_panels_damaged: panels.length,
      damaged_panels_detail: panels,
      pergantian_sparepart: [],
    },
    financial_estimation: {},
  };
}

function panel(name: string, severity: string, damageType: string, extra: any = {}) {
  return {
    panel_name: name,
    panel_severity: severity,
    damage_type: damageType,
    scratches_found: damageType === "scratch" ? 1 : 0,
    dents_found: damageType === "dent" ? 1 : 0,
    broken_found: damageType === "broken" ? 1 : 0,
    requires_replacement: false,
    ...extra,
  };
}

Deno.test("normaliseSeverity falls back to berat on unknown values", () => {
  assertEquals(normaliseSeverity("BERAT"), "berat");
  assertEquals(normaliseSeverity("Sedang"), "sedang");
  assertEquals(normaliseSeverity("mild"), "berat");
  assertEquals(normaliseSeverity(undefined), "berat");
});

Deno.test("severe dent is replacement-only", () => {
  const data = payload([panel("Fender RH", "berat", "dent")]);
  const replaceOnly = applyRepairPolicy(data);
  const p = data.assessment.damaged_panels_detail[0];

  assertEquals(replaceOnly, ["Fender RH"]);
  assertEquals(p.requires_replacement, true);
  assertEquals(p.repair_allowed, false);
  assertEquals(p.recommended_action, "replace");
  assertExists(p.action_reason);
});

Deno.test("moderate dent keeps the repair option", () => {
  const data = payload([panel("Pintu Depan RH", "sedang", "dent")]);
  const replaceOnly = applyRepairPolicy(data);
  const p = data.assessment.damaged_panels_detail[0];

  assertEquals(replaceOnly, []);
  assertEquals(p.repair_allowed, true);
  assertEquals(p.recommended_action, "repair");
  assertEquals(p.requires_replacement, false);
});

Deno.test("severe scratch stays repairable (repaint, not replace)", () => {
  const data = payload([panel("Kap Mesin", "berat", "scratch")]);
  applyRepairPolicy(data);
  const p = data.assessment.damaged_panels_detail[0];

  assertEquals(p.repair_allowed, true);
  assertEquals(p.recommended_action, "repair");
});

Deno.test("broken part is replacement-only regardless of severity", () => {
  const data = payload([panel("Headlamp RH", "ringan", "broken")]);
  const replaceOnly = applyRepairPolicy(data);
  const p = data.assessment.damaged_panels_detail[0];

  assertEquals(replaceOnly, ["Headlamp RH"]);
  assertEquals(p.requires_replacement, true);
  assertEquals(p.repair_allowed, false);
});

Deno.test("quarter replacement adds welded-panel labour and paint items", () => {
  const data = payload([
    panel("Quarter RH", "berat", "dent"),
  ]);
  const summary = applyEstimatorPolicies(data);
  const names = data.assessment.damaged_panels_detail.map((p: any) => p.panel_name);

  assertEquals(summary.quarterSides, ["RH"]);
  assertEquals(summary.derivedItems.length, 6);
  for (const expected of [
    "Bongkar Quarter RH",
    "Las Quarter RH",
    "Cat Side Roof RH",
    "Cat Trisplang RH",
    "Cat Inner Quarter RH",
    "Cat Opening Bagasi",
  ]) {
    assertEquals(names.includes(expected), true, `missing ${expected}`);
  }

  const derived = data.assessment.damaged_panels_detail.find(
    (p: any) => p.panel_name === "Bongkar Quarter RH",
  );
  assertEquals(derived.derived, true);
  assertEquals(derived.pricing_pending, true);
  assertEquals(derived.calculated_cost, 0);
  // Derived labour lines must not inflate the damaged-panel count.
  assertEquals(data.assessment.total_panels_damaged, 1);
});

Deno.test("repairable quarter does not trigger the quarter policy", () => {
  const data = payload([panel("Quarter LH", "sedang", "dent")]);
  const summary = applyEstimatorPolicies(data);

  assertEquals(summary.quarterSides, []);
  assertEquals(summary.derivedItems, []);
  assertEquals(data.assessment.damaged_panels_detail.length, 1);
});

Deno.test("both quarters replaced share a single opening-bagasi paint line", () => {
  const data = payload([
    panel("Quarter RH", "berat", "dent"),
    panel("Quarter LH", "berat", "dent"),
  ]);
  const summary = applyEstimatorPolicies(data);
  const names = data.assessment.damaged_panels_detail.map((p: any) => p.panel_name);

  assertEquals(summary.quarterSides, ["LH", "RH"]);
  assertEquals(summary.derivedItems.length, 11);
  assertEquals(names.filter((n: string) => n === "Cat Opening Bagasi").length, 1);
  assertEquals(data.assessment.total_panels_damaged, 2);
});

Deno.test("labour operations are never marked replace-only", () => {
  const data = payload([
    panel("Isi Freon AC", "ringan", "broken"),
    panel("B/P Kaca Depan", "berat", "broken"),
  ]);
  const replaceOnly = applyRepairPolicy(data);
  const panels = data.assessment.damaged_panels_detail;

  assertEquals(replaceOnly, []);
  for (const p of panels) {
    assertEquals(p.requires_replacement, false);
    assertEquals(p.recommended_action, "labor");
  }
});

Deno.test("running the policy twice is idempotent", () => {
  const data = payload([panel("Quarter RH", "berat", "dent")]);
  applyEstimatorPolicies(data);
  const second = applyQuarterReplacementPolicy(data);

  assertEquals(second, []);
  assertEquals(data.assessment.damaged_panels_detail.length, 7);
});

Deno.test("model-supplied labour line is not duplicated", () => {
  const data = payload([
    panel("Quarter RH", "berat", "dent"),
    panel("Bongkar Quarter RH", "sedang", "labor"),
  ]);
  const summary = applyEstimatorPolicies(data);
  const names = data.assessment.damaged_panels_detail.map((p: any) => p.panel_name);

  assertEquals(names.filter((n: string) => n === "Bongkar Quarter RH").length, 1);
  assertEquals(summary.derivedItems.length, 5);
});
