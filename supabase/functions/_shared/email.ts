// Email normalisation + validation shared by the edge functions.
//
// The registration form used to accept anything non-empty, so a typo
// ("nama@domain", "nama@@x.com") became the applicant's login identity —
// the magic link and the credential email then both bounce, and the applicant
// can never verify their contact address.

/** Practical mailbox shape: local part, one @, dotted domain, TLD ≥ 2 letters. */
const EMAIL_RE = /^[^\s@,;:<>()[\]\\"]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$/;

/** Longest address we accept — RFC 5321 caps a path at 256 octets. */
export const EMAIL_MAX_LENGTH = 254;

/** Trim + lowercase. Lowercase matters: the RLS policy compares addresses. */
export function normaliseEmail(raw: string | null | undefined): string {
  return String(raw ?? "").trim().toLowerCase();
}

/**
 * True when the address can actually receive mail. Returns the reason for a
 * failure so the API can tell the applicant what is wrong with their input.
 */
export function validateEmail(raw: string | null | undefined): { ok: true; email: string } | { ok: false; error: string } {
  const email = normaliseEmail(raw);
  if (email.length === 0) return { ok: false, error: "email is required" };
  if (email.length > EMAIL_MAX_LENGTH) {
    return { ok: false, error: `email must be at most ${EMAIL_MAX_LENGTH} characters` };
  }
  if (!EMAIL_RE.test(email)) {
    return { ok: false, error: "email is not a valid address (contoh: nama@bengkel.co.id)" };
  }
  return { ok: true, email };
}
