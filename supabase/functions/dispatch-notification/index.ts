// ═══════════════════════════════════════════════════════════════════════════════
// dispatch-notification — transport for the notification outbox
//
// Called by a database trigger (public.trg_dispatch_notification) through pg_net,
// with the row id. It reads the row, sends it over the channel the row already
// names, and records the outcome back through
// public.notification_outbox_mark().
//
// Why the outcome is written back rather than assumed: the outbox is the record
// of whether the customer was actually told. A row that silently stays `pending`
// is recoverable (dispatch_pending_notifications re-drives it); a row wrongly
// marked `sent` is a lie that hides a missed notification. So the only path to
// `sent` is a 2xx from the provider.
//
// Channels and providers are read from public.notification_config at call time,
// never hard-coded, so switching email provider or moving from the Meta Cloud API
// to the self-built bridge is a config change with no redeploy:
//
//   email     resend | smtp | none
//   whatsapp  meta | bridge | none
//
// Deliberately reports `skipped` (not `failed`) when the provider is enabled but
// its credentials are absent. That distinction matters: `failed` means the
// provider rejected us and retrying may help; `skipped` means nobody configured
// it yet, and retrying forever would be noise.
//
// Required secrets once you wire it up (none are set today):
//   DISPATCH_SECRET        shared secret; must equal notification_config.dispatch_secret
//   RESEND_API_KEY         email_provider = 'resend'
//   SMTP_URL               email_provider = 'smtp'   (e.g. smtps://user:pass@host:465)
//   WHATSAPP_TOKEN         whatsapp_provider = 'meta'   (Meta Cloud API access token)
//   WHATSAPP_PHONE_ID      whatsapp_provider = 'meta'
//   WHATSAPP_BRIDGE_SECRET whatsapp_provider = 'bridge'
// ═══════════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendSmtp } from "./smtp.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-dispatch-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface OutboxRow {
  id: string;
  user_id: string;
  job_id: string | null;
  kind: string;
  channel: "email" | "whatsapp";
  to_address: string;
  title: string;
  body: string;
  payload: Record<string, unknown>;
  attempts: number;
  /** Transport resolved by notify() at enqueue time: 'meta' | 'bridge' | 'resend' | … */
  provider: string | null;
  /** Why it was sent: 'transactional' | 'marketing' | 'chatbot'. */
  purpose: string;
}

interface Outcome {
  ok: boolean;
  detail: string;
  /** true when the provider simply is not configured — not a delivery failure. */
  skipped?: boolean;
  /**
   * true when this transport is deliberately NOT going to handle the row, so the
   * caller must leave it `pending` rather than recording an outcome.
   *
   * This exists for the local Baileys bridge: the edge function runs in the cloud
   * and the bridge binds 127.0.0.1, so the function cannot reach it. Marking such
   * a row `skipped` would make it invisible to the local drain worker, which only
   * looks at `pending`. Deferring keeps it queued for the worker.
   */
  deferred?: boolean;
}

// ─── channel adapters ────────────────────────────────────────────────────────

async function sendEmailResend(row: OutboxRow, from: string): Promise<Outcome> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return { ok: false, detail: "RESEND_API_KEY not set", skipped: true };

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: [row.to_address],
      subject: row.title,
      text: row.body,
      // `kind` travels as a tag so delivery can be traced per notification type.
      tags: [{ name: "kind", value: row.kind.slice(0, 256) }],
    }),
  });

  if (!res.ok) return { ok: false, detail: `resend ${res.status}: ${(await res.text()).slice(0, 300)}` };
  return { ok: true, detail: "resend accepted" };
}

async function sendEmailSmtp(row: OutboxRow, from: string): Promise<Outcome> {
  // Verified on this project: the edge runtime CAN open outbound raw TCP, so
  // Google SMTP works directly. (An earlier revision of this file claimed
  // otherwise and asked for an HTTP relay — that was wrong.)
  const host = Deno.env.get("SMTP_HOST");
  const portRaw = Deno.env.get("SMTP_PORT");
  const user = Deno.env.get("SMTP_USER");
  const pass = Deno.env.get("SMTP_PASS");

  const missing = [
    !host && "SMTP_HOST", !portRaw && "SMTP_PORT",
    !user && "SMTP_USER", !pass && "SMTP_PASS",
  ].filter(Boolean);

  if (missing.length) {
    // `skipped`, not `failed`: nobody has supplied credentials yet, so an
    // unbounded retry loop would just be noise.
    return { ok: false, detail: `not configured: missing ${missing.join(", ")}`, skipped: true };
  }

  const port = Number(portRaw);
  if (!Number.isFinite(port)) {
    return { ok: false, detail: `SMTP_PORT is not a number: ${portRaw}` };
  }

  // Google displays an App Password as four space-separated groups
  // ("abcd efgh ijkl mnop"). Those spaces are cosmetic, and sending them
  // verbatim makes AUTH fail with 535 — so strip all whitespace.
  const cleanPass = pass!.replace(/\s+/g, "");

  // Prefer the configured display name, falling back to the domain-style header.
  const nameMatch = /^\s*(.*?)\s*<([^>]+)>\s*$/.exec(from ?? "");
  const fromName = nameMatch?.[1] || "Revive";
  const fromEmail = nameMatch?.[2] || user!;

  const res = await sendSmtp(
    { host: host!, port, user: user!, pass: cleanPass, fromName, fromEmail },
    row.to_address,
    row.title,
    row.body,
  );

  return { ok: res.ok, detail: res.ok ? `smtp ${host}:${port}` : res.detail };
}

function normaliseMsisdn(raw: string): string | null {
  const digits = raw.replace(/[^\d]/g, "");
  if (!digits) return null;
  if (digits.startsWith("62")) return digits;
  if (digits.startsWith("0")) return "62" + digits.slice(1);
  if (digits.startsWith("8")) return "62" + digits;
  return digits;
}

async function sendWhatsAppMeta(row: OutboxRow): Promise<Outcome> {
  const token = Deno.env.get("WHATSAPP_TOKEN");
  const phoneId = Deno.env.get("WHATSAPP_PHONE_ID");
  if (!token || !phoneId) {
    return { ok: false, detail: "WHATSAPP_TOKEN / WHATSAPP_PHONE_ID not set", skipped: true };
  }

  const to = normaliseMsisdn(row.to_address);
  if (!to) return { ok: false, detail: `unusable whatsapp number: ${row.to_address}` };

  // Meta only permits free-form text inside an open 24h customer-service window.
  // Business-initiated messages must use an approved template, so if one is
  // configured for this kind we use it — otherwise the send would be accepted
  // here and rejected by Meta.
  const template = row.payload?.wa_template as string | undefined;

  const body = template
    ? {
        messaging_product: "whatsapp",
        to,
        type: "template",
        template: {
          name: template,
          language: { code: (row.payload?.wa_lang as string) ?? "id" },
          components: [
            {
              type: "body",
              parameters: [{ type: "text", text: row.body }],
            },
          ],
        },
      }
    : {
        messaging_product: "whatsapp",
        to,
        type: "text",
        text: { preview_url: false, body: `${row.title}\n\n${row.body}` },
      };

  const res = await fetch(`https://graph.facebook.com/v21.0/${phoneId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) return { ok: false, detail: `meta ${res.status}: ${(await res.text()).slice(0, 300)}` };
  return { ok: true, detail: template ? `meta template ${template}` : "meta text" };
}

async function sendWhatsAppBridge(row: OutboxRow, bridgeUrl: string): Promise<Outcome> {
  const secret = Deno.env.get("WHATSAPP_BRIDGE_SECRET");
  const to = normaliseMsisdn(row.to_address);
  if (!to) return { ok: false, detail: `unusable whatsapp number: ${row.to_address}` };

  // The self-built bridge (Baileys) takes {chatId, message} — a chat JID and the
  // text. An individual JID is "<msisdn>@s.whatsapp.net"; get this wrong and the
  // send fails after the AUTH stage, which reads like a bridge bug.
  //
  // NOTE ON REACHABILITY, because it is the part that actually bites: that
  // bridge binds 127.0.0.1, so this function — which runs in the cloud — cannot
  // reach it directly. Pointing whatsapp_bridge_url at a localhost address will
  // always fail from here. Either expose it through a tunnel and accept the
  // caveat below, or drain the outbox locally with the worker in
  // scripts/whatsapp-drain-worker.py, which talks to the bridge over loopback.
  //
  // The bridge verifies no credential, so an x-bridge-secret header accomplishes
  // nothing on its own. The real control is not exposing it: with no auth on
  // /send, anyone who can reach the URL can send messages as the linked number.
  const res = await fetch(bridgeUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(secret ? { "x-bridge-secret": secret } : {}),
    },
    body: JSON.stringify({
      chatId: `${to}@s.whatsapp.net`,
      message: `${row.title}\n\n${row.body}`,
    }),
  });

  if (res.status === 503) {
    // The bridge is up but the WhatsApp session is not linked. Retrying cannot
    // fix that — a human has to pair the device — so this is `failed`, and the
    // message says which part is missing.
    return {
      ok: false,
      detail: "bridge is not connected to WhatsApp (no linked session); pair it first",
    };
  }
  if (!res.ok) return { ok: false, detail: `bridge ${res.status}: ${(await res.text()).slice(0, 300)}` };

  const body = await res.json().catch(() => ({}));
  if (body?.success === false) {
    return { ok: false, detail: `bridge rejected: ${JSON.stringify(body).slice(0, 200)}` };
  }
  return { ok: true, detail: `bridge accepted (${body?.messageId ?? "no id"})` };
}

// ─── handler ─────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const json = (payload: unknown, status = 200) =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    const { data: cfg } = await admin
      .from("notification_config")
      .select("*")
      .eq("id", 1)
      .single();

    // The secret is enforced before anything is read or sent, so an arbitrary
    // caller cannot use this function as a spamming relay.
    const expected = cfg?.dispatch_secret ?? Deno.env.get("DISPATCH_SECRET") ?? null;
    const presented = req.headers.get("x-dispatch-secret");
    if (!expected || presented !== expected) {
      return json({ error: "forbidden" }, 403);
    }

    const { outbox_id } = await req.json().catch(() => ({ outbox_id: null }));
    if (!outbox_id) return json({ error: "outbox_id required" }, 400);

    const { data: row, error: readErr } = await admin
      .from("notification_outbox")
      .select("*")
      .eq("id", outbox_id)
      .single();

    if (readErr || !row) return json({ error: "outbox row not found" }, 404);
    if (row.status !== "pending") {
      return json({ skipped: true, reason: `already ${row.status}` });
    }

    const outbox = row as OutboxRow;
    let outcome: Outcome;

    // Trust the provider RECORDED ON THE ROW, not the config's current value.
    // notify() already resolved the transport from the row's purpose at enqueue
    // time — a chatbot row carries provider='bridge' while a transactional one
    // carries 'meta'. Reading cfg.whatsapp_provider here would send a chatbot
    // message through Meta, or a customer notification through the consumer
    // bridge, depending on which slot the config happened to hold. The row's
    // value is the decision that was actually made, so it wins.
    let provider: string | null =
      outbox.provider ??
      (outbox.channel === "email" ? cfg?.email_provider : cfg?.whatsapp_provider);

    if (outbox.channel === "email") {
      if (provider === "resend") {
        outcome = await sendEmailResend(outbox, cfg?.email_from ?? "Revive <no-reply@revive.co.id>");
      } else if (provider === "smtp") {
        // `from` must be passed. sendEmailSmtp(row, from) takes two arguments, and
        // calling it with only `row` left `from` undefined — so the From header
        // silently fell back to "Revive <SMTP_USER>" and notification_config.
        // email_from was ignored on this path entirely (while the resend path did
        // honour it, so the two disagreed).
        outcome = await sendEmailSmtp(outbox, cfg?.email_from ?? "");
      } else {
        outcome = { ok: false, detail: `email provider not configured (${provider})`, skipped: true };
      }
    } else {
      if (provider === "meta") {
        outcome = await sendWhatsAppMeta(outbox);
      } else if (provider === "bridge") {
        // Which bridge URL applies depends on the row's purpose: the chatbot
        // number and the notification number are two separate Baileys sessions.
        const bridgeUrl = outbox.purpose === "chatbot"
          ? cfg?.whatsapp_chatbot_bridge_url
          : cfg?.whatsapp_bridge_url;

        if (!bridgeUrl) {
          // No URL configured means the LOCAL drain worker is expected to handle
          // these rows. Defer, so the row stays pending and stays visible to it.
          outcome = {
            ok: false,
            detail: `no bridge url configured for purpose '${outbox.purpose}' — `
              + "leaving for the local drain worker",
            deferred: true,
          };
        } else {
          outcome = await sendWhatsAppBridge(outbox, bridgeUrl);
        }
      } else {
        outcome = { ok: false, detail: `whatsapp provider not configured (${provider})`, skipped: true };
      }
    }

    // A deferred outcome is not an outcome: the transport declined to handle the
    // row on purpose, so record nothing and leave it `pending`.
    if (outcome.deferred) {
      return json({
        outbox_id: outbox.id, channel: outbox.channel, provider,
        status: "pending", deferred: true, detail: outcome.detail,
      });
    }

    const status = outcome.ok ? "sent" : outcome.skipped ? "skipped" : "failed";

    await admin.rpc("notification_outbox_mark", {
      p_outbox_id: outbox.id,
      p_status: status,
      // last_error is a diagnostic, not a user-facing field; truncate so a wall
      // of provider HTML cannot bloat the row.
      p_error: outcome.ok ? null : outcome.detail.slice(0, 1000),
      p_provider: provider ?? null,
    });

    if (!outcome.ok) {
      console.error(`[dispatch] ${outbox.channel}/${provider} ${status} for ${outbox.id}: ${outcome.detail}`);
    }

    return json({ outbox_id: outbox.id, channel: outbox.channel, provider, status, detail: outcome.detail });
  } catch (err) {
    console.error("[dispatch] unhandled:", err);
    return json({ error: String(err) }, 500);
  }
});
