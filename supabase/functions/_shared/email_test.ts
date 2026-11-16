import { normaliseEmail, validateEmail } from "./email.ts";

Deno.test("validateEmail accepts ordinary addresses", () => {
  for (const ok of [
    "nama@bengkel.co.id",
    "budi.santoso+partner@revive.co.id",
    "a@b.id",
    "team_1@sub.domain.co.id",
  ]) {
    const r = validateEmail(ok);
    if (!r.ok) throw new Error(`${ok} should be valid, got ${r.error}`);
  }
});

Deno.test("validateEmail rejects malformed addresses", () => {
  for (const bad of [
    "",
    "   ",
    "nama",
    "nama@",
    "@domain.com",
    "nama@@domain.com",
    "nama@domain",
    "nama@.com",
    "nama@domain..com",
    "nama name@domain.com",
    "nama@domain.c",
    "nama@domain.com, other@x.com",
  ]) {
    const r = validateEmail(bad);
    if (r.ok) throw new Error(`${bad} should be rejected`);
  }
});

Deno.test("validateEmail rejects an over-long address", () => {
  const long = `${"a".repeat(250)}@domain.com`;
  const r = validateEmail(long);
  if (r.ok) throw new Error("expected rejection");
});

Deno.test("normaliseEmail trims and lowercases", () => {
  if (normaliseEmail("  Nama@Bengkel.CO.ID ") !== "nama@bengkel.co.id") {
    throw new Error("normalise failed");
  }
});
