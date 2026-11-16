import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildTrainingContext,
  extractPhotoKeys,
  formatRupiah,
  normaliseTerms,
  rankCases,
  scoreCase,
} from "./training_context.ts";

const agya = {
  id: "case-agya",
  car_make_model: "Toyota Agya (Hatchback Merah)",
  damage_description: "Frontal offset kanan rusak berat.\n- Kap Mesin (Ganti): Rp 600.000\n- Fender RH: Rp 900.000",
  resolved_actual_cost: 4750000,
  created_at: "2026-11-05T02:13:42Z",
};
const ignis = {
  id: "case-ignis",
  car_make_model: "Suzuki Ignis",
  damage_description: "Benturan belakang sedang, bumper belakang pecah.",
  resolved_actual_cost: "1872500",
  created_at: "2026-11-10T02:00:00Z",
};

Deno.test("formatRupiah uses Indonesian separators and drops zero", () => {
  assertEquals(formatRupiah(4750000), "4.750.000");
  assertEquals(formatRupiah("1872500"), "1.872.500");
  assertEquals(formatRupiah(0), "");
  assertEquals(formatRupiah(null), "");
});

Deno.test("normaliseTerms drops short and duplicate words", () => {
  assertEquals(normaliseTerms(["Quarter RH", "quarter", "a", "Suzuki"]).sort(), ["quarter", "rh", "suzuki"]);
});

Deno.test("scoreCase prefers brand/model matches over body matches", () => {
  const terms = normaliseTerms(["Agya"]);
  assertEquals(scoreCase(agya, terms), 3);
  assertEquals(scoreCase(ignis, terms), 0);
});

Deno.test("rankCases puts the most relevant case first", () => {
  const ranked = rankCases([ignis, agya], normaliseTerms(["Agya"]));
  assertEquals(ranked[0].id, "case-agya");
});

Deno.test("rankCases falls back to newest when nothing matches", () => {
  const ranked = rankCases([agya, ignis], []);
  assertEquals(ranked[0].id, "case-ignis");
});

Deno.test("buildTrainingContext formats cases with real cost", () => {
  const ctx = buildTrainingContext({ cases: [agya], terms: ["Kap Mesin"] });
  assertStringIncludes(ctx.text, "CONTOH KASUS BENAR");
  assertStringIncludes(ctx.text, "Toyota Agya (Hatchback Merah)");
  assertStringIncludes(ctx.text, "total jasa riil: Rp4.750.000");
  assertEquals(ctx.usedCaseIds, ["case-agya"]);
});

Deno.test("buildTrainingContext appends reviewer corrections", () => {
  const ctx = buildTrainingContext({
    cases: [agya],
    corrections: [{ panel_name: "Quarter LH", ai_severity: "berat", comment: "sebenarnya sedang" }],
  });
  assertStringIncludes(ctx.text, "KOREKSI REVIEWER");
  assertStringIncludes(ctx.text, 'Panel "Quarter LH"');
  assertEquals(ctx.usedCorrections, 1);
});

Deno.test("buildTrainingContext returns empty text when there is nothing to inject", () => {
  assertEquals(buildTrainingContext({ cases: [] }).text, "");
  assertEquals(buildTrainingContext({ cases: [{ damage_description: "   " }] }).text, "");
});

Deno.test("buildTrainingContext respects the character budget", () => {
  const ctx = buildTrainingContext({ cases: [agya, ignis], maxChars: 400 });
  assertEquals(ctx.usedCaseIds.length <= 1, true);
  assertEquals(ctx.text.length <= 400, true);
});

Deno.test("buildTrainingContext truncates a long case body", () => {
  const longCase = { ...agya, damage_description: "x".repeat(5000) };
  const ctx = buildTrainingContext({ cases: [longCase], caseChars: 200 });
  assertEquals(ctx.text.includes("x".repeat(201)), false);
});

Deno.test("extractPhotoKeys keeps the durable key and drops the signature", () => {
  const keys = extractPhotoKeys([
    "https://1bfeaffe.r2.cloudflarestorage.com/revive-photos/aa11-bb22/estimator/1763251200000_abc.jpg?X-Amz-Expires=300&X-Amz-Signature=deadbeef",
    "https://1bfeaffe.r2.cloudflarestorage.com/revive-photos/aa11-bb22/estimator/1763251200000_abc.jpg?X-Amz-Signature=other",
    "not-a-url",
  ]);
  assertEquals(keys, ["aa11-bb22/estimator/1763251200000_abc.jpg"]);
});
