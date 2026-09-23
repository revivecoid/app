// ═══════════════════════════════════════════════════════════════════════════════
// Minimal SMTP client for the Supabase Edge runtime.
//
// Written because the runtime DOES support outbound raw TCP — verified on this
// project by connecting to smtp.gmail.com:
//   587 → "220 smtp.gmail.com ESMTP ..."   (plain, then STARTTLS)
//   465 → connects; reads empty until the TLS handshake (implicit TLS)
// An earlier version of the dispatch function assumed this was impossible and
// told the operator to stand up an HTTP relay. That was wrong.
//
// Deliberately does NOT need a third-party SMTP library: the whole conversation
// is ten commands, and inlining it avoids a dependency that would need to work
// on this specific runtime.
//
// Ports:
//   465  implicit TLS  → Deno.connectTls
//   587  STARTTLS      → Deno.connect, then Deno.startTls after EHLO
//   anything else is treated as plaintext, which is only sane for a local relay.
// ═══════════════════════════════════════════════════════════════════════════════

export interface SmtpCredentials {
  host: string;
  port: number;
  user: string;
  pass: string;
  fromName: string;
  fromEmail: string;
}

interface SmtpResponse {
  code: number;
  lines: string[];
}

/** Buffered line reader over a connected socket. */
function makeSession(conn: Deno.Conn) {
  let buf = "";
  const decoder = new TextDecoder();

  return {
    conn,
    async readResponse(): Promise<SmtpResponse> {
      const lines: string[] = [];
      // Read until a line carries "NNN " (space) rather than "NNN-" (continuation).
      for (;;) {
        let idx: number;
        while ((idx = buf.indexOf("\r\n")) === -1) {
          const chunk = new Uint8Array(8192);
          const n = await conn.read(chunk);
          if (n === null) throw new Error("SMTP connection closed unexpectedly");
          buf += decoder.decode(chunk.subarray(0, n), { stream: true });
        }
        const line = buf.slice(0, idx);
        buf = buf.slice(idx + 2);
        lines.push(line);
        if (line.length < 4 || line[3] === " ") break;
      }
      const last = lines[lines.length - 1] ?? "";
      return { code: Number.parseInt(last.slice(0, 3), 10), lines };
    },

    async send(line: string): Promise<SmtpResponse> {
      await conn.write(new TextEncoder().encode(line + "\r\n"));
      return this.readResponse();
    },

    async sendRaw(data: string): Promise<SmtpResponse> {
      await conn.write(new TextEncoder().encode(data));
      return this.readResponse();
    },

    async writeOnly(line: string) {
      await conn.write(new TextEncoder().encode(line + "\r\n"));
    },
  };
}

type Session = ReturnType<typeof makeSession>;

/** RFC 2047 encoding — a subject with any non-ASCII byte must be encoded. */
function encodeHeader(value: string): string {
  // eslint-disable-next-line no-control-regex
  if (/^[\x20-\x7E]*$/.test(value)) return value;
  const b64 = btoa(String.fromCharCode(...new TextEncoder().encode(value)));
  return `=?UTF-8?B?${b64}?=`;
}

/** Base64 the body in 76-char lines: sidesteps line-length limits and, because
 *  no line can start with a bare ".", sidesteps dot-stuffing entirely. */
function base64Body(text: string): string {
  const b64 = btoa(String.fromCharCode(...new TextEncoder().encode(text)));
  return (b64.match(/.{1,76}/g) ?? []).join("\r\n");
}

function buildMessage(creds: SmtpCredentials, to: string, subject: string, body: string): string {
  // Some MUAs are strict about the address form in the envelope vs the header.
  const fromAddress = creds.fromEmail;
  return [
    `From: ${encodeHeader(creds.fromName)} <${fromAddress}>`,
    `To: <${to}>`,
    `Subject: ${encodeHeader(subject)}`,
    "MIME-Version: 1.0",
    'Content-Type: text/plain; charset="UTF-8"',
    "Content-Transfer-Encoding: base64",
    "Auto-Submitted: auto-generated",
    "",
    base64Body(body),
  ].join("\r\n");
}

async function upgradeToTls(session: Session, host: string): Promise<Session> {
  const tls = await Deno.startTls(session.conn, { hostname: host });
  return makeSession(tls);
}

export async function sendSmtp(
  creds: SmtpCredentials,
  to: string,
  subject: string,
  body: string,
  timeoutMs = 20_000,
): Promise<{ ok: boolean; detail: string }> {
  let conn: Deno.Conn | null = null;
  const deadline = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error(`SMTP timed out after ${timeoutMs}ms`)), timeoutMs)
  );

  const work = async (): Promise<{ ok: boolean; detail: string }> => {
    // ── connect ──────────────────────────────────────────────────────────────
    const implicitTls = creds.port === 465;
    conn = implicitTls
      ? await Deno.connectTls({ hostname: creds.host, port: creds.port })
      : await Deno.connect({ hostname: creds.host, port: creds.port });

    let session: Session = makeSession(conn);

    const greeting = await session.readResponse();
    if (greeting.code !== 220) {
      return { ok: false, detail: `bad greeting ${greeting.code}: ${greeting.lines.join(" ")}` };
    }

    const ehlo = await session.send(`EHLO revive.co.id`);
    if (ehlo.code !== 250) {
      return { ok: false, detail: `EHLO rejected ${ehlo.code}: ${ehlo.lines.join(" ")}` };
    }

    // ── STARTTLS on the submission port ──────────────────────────────────────
    if (!implicitTls && creds.port === 587) {
      const starttls = await session.send("STARTTLS");
      if (starttls.code !== 220) {
        return { ok: false, detail: `STARTTLS rejected ${starttls.code}` };
      }
      session = await upgradeToTls(session, creds.host);
      const reEhlo = await session.send("EHLO revive.co.id");
      if (reEhlo.code !== 250) {
        return { ok: false, detail: `EHLO after STARTTLS rejected ${reEhlo.code}` };
      }
    }

    // ── authenticate (AUTH LOGIN, base64) ────────────────────────────────────
    const authStart = await session.send("AUTH LOGIN");
    if (authStart.code !== 334) {
      return { ok: false, detail: `AUTH LOGIN rejected ${authStart.code}: ${authStart.lines.join(" ")}` };
    }
    const userResp = await session.send(btoa(creds.user));
    if (userResp.code !== 334) {
      return { ok: false, detail: `username rejected ${userResp.code}: ${userResp.lines.join(" ")}` };
    }
    const passResp = await session.send(btoa(creds.pass));
    if (passResp.code !== 235) {
      // 535 is the normal "wrong credentials" answer. Surface it verbatim — the
      // operator needs to know it is a credential problem, not a transport one.
      return {
        ok: false,
        detail: `auth failed ${passResp.code}: ${passResp.lines.join(" ")}`.slice(0, 400),
      };
    }

    // ── envelope ─────────────────────────────────────────────────────────────
    const mailFrom = await session.send(`MAIL FROM:<${creds.fromEmail}>`);
    if (mailFrom.code !== 250) {
      return { ok: false, detail: `MAIL FROM rejected ${mailFrom.code}: ${mailFrom.lines.join(" ")}` };
    }
    // Deliberately no SMTPUTF8 / BODY=8BITMIME options: the envelope is ASCII
    // here, and the body is base64, so neither is needed.
    const rcptTo = await session.send(`RCPT TO:<${to}>`);
    if (rcptTo.code !== 250 && rcptTo.code !== 251) {
      return { ok: false, detail: `RCPT TO rejected ${rcptTo.code}: ${rcptTo.lines.join(" ")}` };
    }

    const data = await session.send("DATA");
    if (data.code !== 354) {
      return { ok: false, detail: `DATA rejected ${data.code}: ${data.lines.join(" ")}` };
    }

    // Terminating sequence: CRLF "." CRLF. Safe without dot-stuffing because the
    // base64 payload cannot contain a line starting with ".".
    const message = buildMessage(creds, to, subject, body) + "\r\n.\r\n";
    const accepted = await session.sendRaw(message);
    if (accepted.code !== 250) {
      return { ok: false, detail: `message rejected ${accepted.code}: ${accepted.lines.join(" ")}` };
    }

    try { await session.send("QUIT"); } catch { /* server may drop us; the mail is accepted */ }

    return { ok: true, detail: `smtp accepted (${accepted.lines.join(" ").slice(0, 120)})` };
  };

  try {
    return await Promise.race([work(), deadline]);
  } catch (e) {
    return { ok: false, detail: `smtp transport error: ${e}`.slice(0, 400) };
  } finally {
    try { conn?.close(); } catch { /* already closed */ }
  }
}
