// send-partner-otp — issues (or re-issues) a contact verification code.
//
// Called by the applicant dashboard AFTER the application is filed:
//   • submit-partner-application sends the first pair of codes itself
//   • this function exists for "kirim ulang" (resend) only
//
// Abuse control lives in _shared/partner_otp.ts and is enforced here:
//   6-digit crypto code, SHA-256 at rest, 10 min TTL, 5 verify attempts,
//   at most 3 resends, 60 s between sends.
//
// Body:   { application_id: string, channel: 'whatsapp' | 'email' }
// Returns { sent, channel, retry_after_seconds, resends_left, expires_in_minutes }
//       | { verified: true }                       already verified
//       | { error, retry_after_seconds? }         429 when throttled

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  type Channel,
  expiresAtFrom,
  generateOtp,
  OTP_RESEND_COOLDOWN_SECONDS,
  OTP_RESEND_LIMIT,
  OTP_TTL_MINUTES,
  resendDecision,
  sha256hex,
  type ChallengeRow,
} from "../_shared/partner_otp.ts";
import { queueOtp } from "../_shared/partner_otp_delivery.ts";

const CORS = {
  "Access-Control-Allow-Origin": "https://revive.co.id",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);
    const token = authHeader.replace("Bearer ", "");

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      auth: { persistSession: false },
    });
    const { data: { user }, error: userError } = await anon.auth.getUser(token);
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json().catch(() => ({}));
    const applicationId = String(body.application_id ?? "").trim();
    const channel = String(body.channel ?? "").trim() as Channel;
    if (!applicationId) return json({ error: "application_id required" }, 400);
    if (channel !== "whatsapp" && channel !== "email") {
      return json({ error: "channel must be whatsapp or email" }, 400);
    }

    // The caller must own the application: either the guest session that filed
    // it (submitted_by) or the account created for it (auth_user_id).
    const { data: app, error: appErr } = await admin
      .from("partner_applications")
      .select("id, shop_name, phone, email, submitted_by, auth_user_id, status")
      .eq("id", applicationId)
      .single();
    if (appErr || !app) return json({ error: "Pendaftaran tidak ditemukan." }, 404);
    const owns = app.submitted_by === user.id || app.auth_user_id === user.id;
    if (!owns) return json({ error: "Forbidden" }, 403);

    const toAddress = channel === "whatsapp" ? String(app.phone ?? "") : String(app.email ?? "");
    if (!toAddress) return json({ error: `Alamat ${channel} tidak tersedia pada pendaftaran ini.` }, 400);

    const { data: cfg } = await admin
      .from("notification_config")
      .select("enabled, whatsapp_provider, email_provider")
      .eq("id", 1)
      .single();
    if (!cfg?.enabled) return json({ error: "Pengiriman notifikasi sedang dimatikan." }, 503);
    const provider = channel === "whatsapp" ? cfg.whatsapp_provider : cfg.email_provider;
    if (!provider || provider === "none") {
      return json({ error: `Kanal ${channel} belum dikonfigurasi.` }, 503);
    }

    const { data: existing } = await admin
      .from("partner_contact_otps")
      .select("attempts, resend_count, last_sent_at, expires_at, verified_at")
      .eq("application_id", applicationId)
      .eq("channel", channel)
      .maybeSingle();

    const row = existing as ChallengeRow | null;
    const now = new Date();
    const decision = resendDecision(row, now);
    if (!decision.allowed) {
      if (row?.verified_at) return json({ verified: true, channel }, 200);
      return json(
        { error: decision.reason, retry_after_seconds: decision.retryAfterSeconds },
        429,
      );
    }

    const code = generateOtp();
    const hash = await sha256hex(code);
    const { error: upsertErr } = await admin
      .from("partner_contact_otps")
      .upsert({
        application_id: applicationId,
        channel,
        code_hash: hash,
        to_address: toAddress,
        expires_at: expiresAtFrom(now),
        attempts: 0,
        resend_count: (row?.resend_count ?? 0) + 1,
        last_sent_at: now.toISOString(),
        verified_at: null,
        last_error: null,
      }, { onConflict: "application_id,channel" });
    if (upsertErr) throw upsertErr;

    const delivery = await queueOtp(admin, {
      applicationId,
      userId: String(app.auth_user_id ?? app.submitted_by ?? user.id),
      channel,
      toAddress,
      code,
      shopName: app.shop_name,
      provider,
    });

    if (!delivery.queued) {
      await admin
        .from("partner_contact_otps")
        .update({ last_error: delivery.error ?? "queue failed" })
        .eq("application_id", applicationId)
        .eq("channel", channel);
      return json({ error: `Gagal mengantrekan ${channel}: ${delivery.error}` }, 502);
    }

    return json({
      sent: true,
      channel,
      retry_after_seconds: OTP_RESEND_COOLDOWN_SECONDS,
      resends_left: Math.max(0, OTP_RESEND_LIMIT - ((row?.resend_count ?? 0) + 1)),
      expires_in_minutes: OTP_TTL_MINUTES,
    });
  } catch (err) {
    console.error("[send-partner-otp]", err);
    return json({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
