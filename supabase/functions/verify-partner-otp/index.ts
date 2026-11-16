// verify-partner-otp — checks a contact verification code.
//
// Verification is what makes the phone number and email address trustworthy:
// the applicant can only answer with a code delivered to that address, and the
// challenge was created by submit-partner-application, so a caller cannot
// "verify" a contact for an application that was never filed.
//
// Attempts are burned on every wrong guess and the code locks after
// OTP_MAX_ATTEMPTS, so a 6-digit space cannot be brute-forced. A fresh code
// requires the 60 s cooldown in send-partner-otp.
//
// Body:   { application_id, channel: 'whatsapp'|'email', code: '123456' }
// Returns { verified: true, channel, both_verified } | { verified: false, error, attempts_left, locked }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  type ChallengeRow,
  type Channel,
  sha256hex,
  verifyDecision,
} from "../_shared/partner_otp.ts";

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
    if (!authHeader) return json({ verified: false, error: "Missing Authorization header" }, 401);
    const token = authHeader.replace("Bearer ", "");

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      auth: { persistSession: false },
    });
    const { data: { user }, error: userError } = await anon.auth.getUser(token);
    if (userError || !user) return json({ verified: false, error: "Unauthorized" }, 401);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json().catch(() => ({}));
    const applicationId = String(body.application_id ?? "").trim();
    const channel = String(body.channel ?? "").trim() as Channel;
    const code = String(body.code ?? "").replace(/\D/g, "");
    if (!applicationId) return json({ verified: false, error: "application_id required" }, 400);
    if (channel !== "whatsapp" && channel !== "email") {
      return json({ verified: false, error: "channel must be whatsapp or email" }, 400);
    }
    if (!/^\d{6}$/.test(code)) {
      return json({ verified: false, error: "Kode harus 6 digit." }, 400);
    }

    const { data: app, error: appErr } = await admin
      .from("partner_applications")
      .select("id, submitted_by, auth_user_id, wa_verified, email_verified")
      .eq("id", applicationId)
      .single();
    if (appErr || !app) return json({ verified: false, error: "Pendaftaran tidak ditemukan." }, 404);
    const owns = app.submitted_by === user.id || app.auth_user_id === user.id;
    if (!owns) return json({ verified: false, error: "Forbidden" }, 403);

    const { data: challenge } = await admin
      .from("partner_contact_otps")
      .select("code_hash, attempts, resend_count, last_sent_at, expires_at, verified_at")
      .eq("application_id", applicationId)
      .eq("channel", channel)
      .maybeSingle();

    const row = challenge as (ChallengeRow & { code_hash: string }) | null;
    const now = new Date();
    const presentedHash = await sha256hex(code);
    const outcome = verifyDecision(row, row?.code_hash ?? "", presentedHash, now);

    if (!outcome.verified) {
      // Burn the attempt. The counter is what makes a 6-digit code safe.
      if (row && !row.verified_at) {
        await admin
          .from("partner_contact_otps")
          .update({ attempts: row.attempts + 1 })
          .eq("application_id", applicationId)
          .eq("channel", channel);
      }
      return json({
        verified: false,
        error: outcome.error,
        attempts_left: outcome.attemptsLeft,
        locked: outcome.locked,
      });
    }

    if (!row?.verified_at) {
      await admin
        .from("partner_contact_otps")
        .update({ verified_at: now.toISOString() })
        .eq("application_id", applicationId)
        .eq("channel", channel);
    }

    const flags = channel === "whatsapp"
      ? { wa_verified: true }
      : { email_verified: true };
    const both = channel === "whatsapp"
      ? app.email_verified === true
      : app.wa_verified === true;

    await admin
      .from("partner_applications")
      .update({ ...flags, ...(both ? { contacts_verified_at: now.toISOString() } : {}) })
      .eq("id", applicationId);

    return json({ verified: true, channel, both_verified: both });
  } catch (err) {
    console.error("[verify-partner-otp]", err);
    return json({ verified: false, error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
