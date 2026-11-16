// partner_otp_delivery — puts a verification code into notification_outbox.
//
// Deliberately NOT public.notify(): that helper fans out to users, partners and
// admins from memberships, and requires a notification_preferences consent row
// before either channel is allowed. A partner applicant is anonymous at this
// point — no membership, no preference row — so notify() would silently enqueue
// nothing and the applicant would sit waiting for a code that was never sent.
//
// Inserting the outbox row directly also keeps the transport configurable: the
// provider recorded on the row is whatever notification_config says today
// (whatsapp: bridge|meta, email: smtp|resend), and dispatch-notification honours
// the row's value rather than re-reading config.

import type { Channel } from "./partner_otp.ts";

export interface DeliveryResult {
  queued: boolean;
  error?: string;
}

export interface QueueOtpOptions {
  applicationId: string;
  /** Must be a real auth uid — notification_outbox.user_id is NOT NULL. */
  userId: string;
  channel: Channel;
  toAddress: string;
  code: string;
  shopName?: string | null;
  provider: string | null;
}

export function otpTitle(channel: Channel): string {
  return channel === "whatsapp"
    ? "Kode Verifikasi Revive"
    : "[Revive] Kode Verifikasi Pendaftaran Mitra";
}

export function otpBody(channel: Channel, code: string, shopName?: string | null): string {
  const shop = (shopName ?? "").trim();
  const subject = shop.length > 0 ? `pendaftaran mitra ${shop}` : "pendaftaran mitra Anda";
  if (channel === "whatsapp") {
    return (
      `Kode verifikasi ${subject}: *${code}*\n\n` +
      `Berlaku 10 menit. Jangan bagikan kode ini kepada siapa pun.`
    );
  }
  return (
    `Halo,\n\n` +
    `Kode verifikasi untuk ${subject} adalah:\n\n` +
    `    ${code}\n\n` +
    `Kode ini berlaku 10 menit dan hanya dapat dipakai sekali.\n` +
    `Jika Anda tidak merasa mendaftar sebagai mitra Revive, abaikan email ini.\n\n` +
    `Salam,\nTim Revive\npartner@revive.co.id`
  );
}

/** `admin` is a service-role supabase-js client. */
// deno-lint-ignore no-explicit-any
export async function queueOtp(admin: any, opts: QueueOtpOptions): Promise<DeliveryResult> {
  const { error } = await admin.from("notification_outbox").insert({
    user_id: opts.userId,
    job_id: null,
    kind: "partner_otp",
    channel: opts.channel,
    to_address: opts.toAddress,
    title: otpTitle(opts.channel),
    body: otpBody(opts.channel, opts.code, opts.shopName),
    payload: { application_id: opts.applicationId, otp_channel: opts.channel },
    status: "pending",
    provider: opts.provider,
    purpose: "transactional",
  });
  if (error) return { queued: false, error: error.message };
  return { queued: true };
}
