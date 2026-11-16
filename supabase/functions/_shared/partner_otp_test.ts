import {
  constantTimeEqual,
  expiresAtFrom,
  generateOtp,
  normaliseMsisdn,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_LIMIT,
  resendDecision,
  sha256hex,
  verifyDecision,
  type ChallengeRow,
} from "./partner_otp.ts";

function assert(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}
function assertEquals<T>(actual: T, expected: T, msg: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

const NOW = new Date("2026-11-16T07:00:00Z");

function row(over: Partial<ChallengeRow> = {}): ChallengeRow {
  return {
    attempts: 0,
    resend_count: 0,
    last_sent_at: NOW.toISOString(),
    expires_at: expiresAtFrom(NOW),
    verified_at: null,
    ...over,
  };
}

// ── normaliseMsisdn ─────────────────────────────────────────────────────────
Deno.test("normaliseMsisdn accepts the three shapes the form produces", () => {
  assertEquals(normaliseMsisdn("081234567890"), "6281234567890", "leading zero");
  assertEquals(normaliseMsisdn("81234567890"), "6281234567890", "bare 8");
  assertEquals(normaliseMsisdn("6281234567890"), "6281234567890", "already 62");
  assertEquals(normaliseMsisdn("+62 812-3456-7890"), "6281234567890", "punctuation");
});

Deno.test("normaliseMsisdn rejects what is not an Indonesian mobile", () => {
  assertEquals(normaliseMsisdn(""), "", "empty");
  assertEquals(normaliseMsisdn("12345"), "", "too short");
  assertEquals(normaliseMsisdn("0212345678"), "62212345678", "landline keeps its shape but is not 8…");
});

// ── generateOtp ─────────────────────────────────────────────────────────────
Deno.test("generateOtp is six digits and not constant", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 50; i++) {
    const code = generateOtp();
    assert(/^\d{6}$/.test(code), `not 6 digits: ${code}`);
    seen.add(code);
  }
  assert(seen.size > 40, `too many collisions: ${seen.size}/50`);
});

// ── hashing ─────────────────────────────────────────────────────────────────
Deno.test("sha256hex is stable and constantTimeEqual compares full length", async () => {
  const a = await sha256hex("123456");
  assertEquals(a, await sha256hex("123456"), "same input, same hash");
  assert(a !== await sha256hex("123457"), "different input, different hash");
  assert(constantTimeEqual(a, a), "identical digests match");
  assert(!constantTimeEqual(a, a.slice(0, -1)), "different length never matches");
  assert(!constantTimeEqual(a, "0".repeat(a.length)), "same length, different value");
});

// ── resend policy ───────────────────────────────────────────────────────────
Deno.test("first send is always allowed", () => {
  assertEquals(resendDecision(null, NOW).allowed, true, "no row yet");
});

Deno.test("resend inside the cooldown is refused with the remaining seconds", () => {
  const d = resendDecision(row({ last_sent_at: new Date(NOW.getTime() - 15_000).toISOString() }), NOW);
  assertEquals(d.allowed, false, "15s after a send");
  assertEquals(d.retryAfterSeconds, 45, "45s left of a 60s cooldown");
});

Deno.test("resend after the cooldown is allowed until the limit", () => {
  const base = { last_sent_at: new Date(NOW.getTime() - 61_000).toISOString() };
  assertEquals(resendDecision(row({ ...base, resend_count: 0 }), NOW).allowed, true, "first resend");
  assertEquals(resendDecision(row({ ...base, resend_count: OTP_RESEND_LIMIT - 1 }), NOW).allowed, true, "last resend");
  const capped = resendDecision(row({ ...base, resend_count: OTP_RESEND_LIMIT }), NOW);
  assertEquals(capped.allowed, false, "limit reached");
  assert((capped.reason ?? "").includes("resend limit"), "reason explains the cap");
});

Deno.test("a verified challenge is never re-sent", () => {
  const d = resendDecision(
    row({ verified_at: NOW.toISOString(), last_sent_at: new Date(NOW.getTime() - 3_600_000).toISOString() }),
    NOW,
  );
  assertEquals(d.allowed, false, "already verified");
  assertEquals(d.reason, "already verified", "reason");
});

// ── verify policy ───────────────────────────────────────────────────────────
Deno.test("correct code verifies once", () => {
  const out = verifyDecision(row(), "aaa", "aaa", NOW);
  assertEquals(out.verified, true, "match");
});

Deno.test("wrong code burns an attempt and reports what is left", () => {
  const out = verifyDecision(row({ attempts: 1 }), "aaa", "bbb", NOW);
  assertEquals(out.verified, false, "mismatch");
  assertEquals(out.attemptsLeft, OTP_MAX_ATTEMPTS - 2, "attempts left");
  assert(!out.locked, "still open");
});

Deno.test("the last wrong attempt locks the code", () => {
  const out = verifyDecision(row({ attempts: OTP_MAX_ATTEMPTS - 1 }), "aaa", "bbb", NOW);
  assertEquals(out.verified, false, "mismatch");
  assertEquals(out.attemptsLeft, 0, "no attempts left");
  assertEquals(out.locked, true, "locked");
});

Deno.test("expired and unknown codes are locked, verified ones stay verified", () => {
  const expired = verifyDecision(
    row({ expires_at: new Date(NOW.getTime() - 1000).toISOString() }),
    "aaa",
    "aaa",
    NOW,
  );
  assertEquals(expired.verified, false, "expired cannot verify");
  assertEquals(expired.locked, true, "expired is locked");

  const unknown = verifyDecision(null, "aaa", "aaa", NOW);
  assertEquals(unknown.verified, false, "no row");
  assertEquals(unknown.locked, true, "no row is locked");

  const done = verifyDecision(row({ verified_at: NOW.toISOString() }), "aaa", "bbb", NOW);
  assertEquals(done.verified, true, "idempotent success");
});
