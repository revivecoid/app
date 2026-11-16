// partner_otp — contact verification challenges for partner applications.
//
// Why this module exists at all: the first implementation asked public.notify()
// to deliver the code. notify() is a *broadcast* helper — it resolves recipients
// from users/memberships and requires a notification_preferences consent row, so
// a phone number that is not yet a user gets nothing. It also has a different
// signature than the call site used, so the RPC failed outright. Verification
// therefore never reached anybody.
//
// The rules that matter are here, not in the functions, so they can be tested:
//   • a code is 6 digits from crypto.getRandomValues (not Math.random)
//   • only its SHA-256 is stored
//   • 10 minute TTL, 5 attempts, 3 resends, 60 second cooldown between sends

export type Channel = "whatsapp" | "email";

export const OTP_TTL_MINUTES = 10;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_RESEND_LIMIT = 3;
export const OTP_RESEND_COOLDOWN_SECONDS = 60;

export interface ChallengeRow {
  attempts: number;
  resend_count: number;
  last_sent_at: string;
  expires_at: string;
  verified_at: string | null;
}

export interface Decision {
  allowed: boolean;
  /** Seconds until another send is allowed; 0 when allowed. */
  retryAfterSeconds: number;
  reason?: string;
}

/**
 * Normalise an Indonesian mobile number to MSISDN form (62…, digits only).
 * Accepts the three shapes the form and the bridge see: 08…, 8…, 62…
 * Returns "" when the input cannot be a mobile number.
 */
export function normaliseMsisdn(raw: string | null | undefined): string {
  const digits = String(raw ?? "").replace(/\D/g, "");
  let msisdn = digits;
  if (digits.startsWith("0")) msisdn = "62" + digits.slice(1);
  else if (digits.startsWith("8")) msisdn = "62" + digits;

  // 62 + 8… : short local numbers are 9-10 digits, the longest valid is 13.
  if (!msisdn.startsWith("62")) return "";
  if (msisdn.length < 10 || msisdn.length > 15) return "";
  return msisdn;
}

/** Six digits, uniformly distributed. Math.random() is not good enough. */
export function generateOtp(): string {
  const buf = new Uint8Array(4);
  crypto.getRandomValues(buf);
  const n = ((buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3]) >>> 0;
  return String(100000 + (n % 900000));
}

export async function sha256hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Compare two hex digests without an early exit on the first differing byte. */
export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function expiresAtFrom(now: Date): string {
  return new Date(now.getTime() + OTP_TTL_MINUTES * 60_000).toISOString();
}

/**
 * May this address be sent another code right now?
 * `row` is null when nothing has been sent yet (the submit-time first send).
 */
export function resendDecision(row: ChallengeRow | null, now: Date): Decision {
  if (!row) return { allowed: true, retryAfterSeconds: 0 };
  if (row.verified_at) {
    return { allowed: false, retryAfterSeconds: 0, reason: "already verified" };
  }

  const sinceLastSend = (now.getTime() - new Date(row.last_sent_at).getTime()) / 1000;
  if (sinceLastSend < OTP_RESEND_COOLDOWN_SECONDS) {
    return {
      allowed: false,
      retryAfterSeconds: Math.ceil(OTP_RESEND_COOLDOWN_SECONDS - sinceLastSend),
      reason: "cooldown",
    };
  }

  if (row.resend_count >= OTP_RESEND_LIMIT) {
    return {
      allowed: false,
      retryAfterSeconds: 0,
      reason: "resend limit reached — hubungi partner@revive.co.id",
    };
  }

  return { allowed: true, retryAfterSeconds: 0 };
}

export interface VerifyOutcome {
  verified: boolean;
  error?: string;
  attemptsLeft: number;
  /** True when the code can no longer be tried and a new one is required. */
  locked: boolean;
}

export function verifyDecision(
  row: ChallengeRow | null,
  storedHash: string,
  presentedHash: string,
  now: Date,
): VerifyOutcome {
  if (!row) {
    return { verified: false, error: "Kode tidak ditemukan. Kirim ulang kode baru.", attemptsLeft: 0, locked: true };
  }
  if (row.verified_at) {
    return { verified: true, attemptsLeft: 0, locked: false };
  }
  if (new Date(row.expires_at).getTime() < now.getTime()) {
    return { verified: false, error: "Kode kedaluwarsa. Kirim ulang kode baru.", attemptsLeft: 0, locked: true };
  }
  if (row.attempts >= OTP_MAX_ATTEMPTS) {
    return {
      verified: false,
      error: "Terlalu banyak percobaan. Kirim ulang kode baru.",
      attemptsLeft: 0,
      locked: true,
    };
  }
  if (constantTimeEqual(storedHash, presentedHash)) {
    return { verified: true, attemptsLeft: 0, locked: false };
  }
  const left = OTP_MAX_ATTEMPTS - row.attempts - 1;
  return {
    verified: false,
    error: left > 0 ? `Kode salah. Sisa ${left} percobaan.` : "Kode salah. Kirim ulang kode baru.",
    attemptsLeft: left,
    locked: left <= 0,
  };
}
