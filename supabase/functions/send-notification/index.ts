import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STATUS_MESSAGES: Record<string, { title: string; body: string; type: string }> = {
  "2_estimated": { title: "Estimasi Kerusakan Selesai", body: "AI vision kami telah selesai menganalisis kerusakan kendaraan Anda. Tinjau hasil estimasi dan konfirmasi booking.", type: "status_update" },
  "3_confirmed": { title: "Booking Dikonfirmasi", body: "Workshop kami menerima booking Anda. Tim kami akan segera menghubungi Anda untuk konfirmasi jadwal.", type: "status_update" },
  "4_scheduled": { title: "Jadwal Masuk Ditetapkan", body: "Kendaraan Anda telah dijadwalkan untuk masuk ke bengkel. Pastikan kendaraan siap pada waktu yang ditentukan.", type: "status_update" },
  "5_admitted":  { title: "Kendaraan Diterima di Bengkel", body: "Kendaraan Anda telah diterima dan sedang dalam pemeriksaan awal oleh tim teknisi kami.", type: "status_update" },
  "6_body_paint":{ title: "Proses Body Paint Dimulai", body: "Kendaraan Anda sedang dalam proses perbaikan di divisi Body dan Paint. Kami akan memberi tahu Anda saat selesai.", type: "status_update" },
  "7_qc":        { title: "Quality Control", body: "Perbaikan hampir selesai! Kendaraan Anda sedang memasuki tahap Quality Control untuk memastikan standar terbaik.", type: "status_update" },
  "8_ready":     { title: "Kendaraan Siap Diambil!", body: "Kendaraan Anda telah selesai diperbaiki dan siap untuk diambil. Silakan datang ke workshop kami.", type: "pickup_ready" },
  "9_done":      { title: "Terima Kasih!", body: "Kendaraan Anda telah diserahkan. Kami harap Anda puas dengan layanan Revive. Sampai jumpa!", type: "general" },
};

function buildEmailHtml(title: string, body: string, jobId: string): string {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    body{font-family:-apple-system,sans-serif;background:#f5f5f5;margin:0;padding:20px}
    .card{background:#fff;border-radius:12px;max-width:500px;margin:0 auto;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.08)}
    .header{background:#D10721;padding:24px;text-align:center}
    .header h2{color:#fff;margin:12px 0 0;font-size:20px}
    .body-content{padding:24px}
    .body-content p{color:#444;line-height:1.6}
    .footer{background:#f9f9f9;padding:16px 24px;text-align:center;font-size:12px;color:#999;border-top:1px solid #eee}
    .btn{display:inline-block;background:#D10721;color:#fff;text-decoration:none;padding:12px 28px;border-radius:8px;font-weight:700;margin-top:16px}
  </style></head><body><div class="card">
    <div class="header"><h2>Revive Auto Repair</h2></div>
    <div class="body-content">
      <h3 style="color:#1D1C1D;margin-top:0">${title}</h3>
      <p>${body}</p>
      <p>Untuk melihat status terkini kendaraan Anda, buka aplikasi Revive.</p>
      <a class="btn" href="https://revive.co.id">Buka Aplikasi</a>
    </div>
    <div class="footer">Job ID: ${jobId}<br>&#169; Revive Auto Repair</div>
  </div></body></html>`;
}

async function sendWhatsApp(toNumber: string, customerName: string, title: string, body: string): Promise<void> {
  const enabled = Deno.env.get("WHATSAPP_ENABLED") === "true";
  if (!enabled) { console.log("[WhatsApp] Skipped: WHATSAPP_ENABLED != true"); return; }
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const accessToken   = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  if (!phoneNumberId || !accessToken) { console.warn("[WhatsApp] Missing env vars"); return; }
  const cleaned = toNumber.replace(/\D/g, "");
  const withCC  = cleaned.startsWith("0") ? "62" + cleaned.slice(1) : cleaned;
  const res = await fetch(`https://graph.facebook.com/v19.0/${phoneNumberId}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${accessToken}` },
    body: JSON.stringify({
      messaging_product: "whatsapp", to: withCC, type: "template",
      template: { name: "booking_status_update", language: { code: "id" },
        components: [{ type: "body", parameters: [
          { type: "text", text: customerName },
          { type: "text", text: title },
          { type: "text", text: body },
        ]}] },
    }),
  });
  if (!res.ok) console.error("[WhatsApp] Failed:", await res.text());
  else console.log("[WhatsApp] Sent to", withCC);
}

async function sendEmail(toEmail: string, title: string, body: string, jobId: string): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) { console.warn("[Email] RESEND_API_KEY not set"); return; }
  const fromAddress = "Revive Auto Repair <noreply@revive.co.id>";
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
    body: JSON.stringify({ from: fromAddress, to: [toEmail], subject: title, html: buildEmailHtml(title, body, jobId) }),
  });
  if (!res.ok) console.error("[Email] Failed:", await res.text());
  else console.log("[Email] Sent to", toEmail);
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const supabaseUrl     = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase        = createClient(supabaseUrl, serviceRoleKey);

  let payload: { job_id: string; customer_id: string; old_status: string; new_status: string };
  try { payload = await req.json(); }
  catch { return new Response("Invalid JSON", { status: 400 }); }

  const { job_id, customer_id, new_status } = payload;
  const message = STATUS_MESSAGES[new_status];
  if (!message) {
    console.log(`[Notification] No message for status: ${new_status}`);
    return new Response(JSON.stringify({ skipped: true }), { status: 200 });
  }

  const { data: prefs } = await supabase
    .from("notification_preferences")
    .select("in_app, email, whatsapp, email_address, whatsapp_number")
    .eq("user_id", customer_id)
    .maybeSingle();

  const { data: profile } = await supabase
    .from("profiles").select("full_name").eq("id", customer_id).maybeSingle();

  const customerName = (profile as any)?.full_name ?? "Pelanggan";
  const results: Record<string, string> = {};

  // 1. In-App
  if ((prefs as any)?.in_app !== false) {
    const { error } = await supabase.from("notifications").insert({
      user_id: customer_id, job_id, title: message.title, body: message.body, type: message.type,
    });
    results.in_app = error ? "error" : "sent";
  } else { results.in_app = "disabled"; }

  // 2. Email
  if ((prefs as any)?.email !== false && (prefs as any)?.email_address) {
    await sendEmail((prefs as any).email_address, message.title, message.body, job_id);
    results.email = "sent";
  } else { results.email = (prefs as any)?.email !== false ? "no_address" : "disabled"; }

  // 3. WhatsApp
  if ((prefs as any)?.whatsapp === true && (prefs as any)?.whatsapp_number) {
    await sendWhatsApp((prefs as any).whatsapp_number, customerName, message.title, message.body);
    results.whatsapp = "sent";
  } else { results.whatsapp = (prefs as any)?.whatsapp ? "no_number" : "disabled"; }

  console.log(`[Notification] Job ${job_id} -> ${new_status}:`, results);
  return new Response(JSON.stringify({ success: true, results }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
