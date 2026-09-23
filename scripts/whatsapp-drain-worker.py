#!/usr/bin/env python3
"""Send queued WhatsApp notifications through the LOCAL Baileys bridge.

Why this exists instead of an edge function:

    The dispatch-notification edge function runs in Supabase's cloud. The
    WhatsApp bridge (hermes scripts/whatsapp-bridge, Baileys) binds 127.0.0.1,
    so the function cannot reach it at all — any bridge URL it were given would
    have to be a public tunnel, and that bridge has NO authentication on /send.
    Exposing it would let anyone who finds the URL send WhatsApp messages from
    the linked number.

So WhatsApp sends happen here, on the machine next to the bridge, over loopback.
Email is unaffected and keeps going through the edge function.

HOW THE TWO HALVES AGREE

    notification_config.whatsapp_provider = 'bridge'
    notification_config.whatsapp_bridge_url = NULL

    With the URL NULL the edge function DEFERS whatsapp rows (leaves them
    `pending`) instead of marking them handled, which is exactly the state this
    worker picks up. Set a URL and the function takes over instead — useful once
    the bridge is behind an authenticated tunnel.

USAGE

    python whatsapp-drain-worker.py            # one pass, then exit
    python whatsapp-drain-worker.py --limit 20
    python whatsapp-drain-worker.py --watch    # loop every 60s
    python whatsapp-drain-worker.py --dry-run  # report, send nothing

    Schedule it (Task Scheduler / cron) every minute or two.

REQUIRED ENVIRONMENT

    SUPABASE_URL                 e.g. https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY    service role — this worker must read the outbox
                                 and record outcomes, and after
                                 20260923_harden_notification_rpcs.sql only
                                 service_role may call notification_outbox_mark

    The service key is a full-tenant credential. Keep it in the environment or a
    file this process can read; do not paste it into the repository.

EXIT CODES
    0  completed a pass (whether or not anything needed sending)
    2  the bridge is not reachable or not paired — nothing was marked, rows were
       left for the next run
    1  unexpected error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

BRIDGE_DEFAULT = "http://127.0.0.1:3000"
TIMEOUT = 30


# ─── user-facing error text, translated to plain language ─────────────────────

def explain(http_status: int | None, body: str) -> str:
    """Turn a bridge response into something an operator can act on."""
    if http_status == 503:
        return ("bridge is running but not paired with WhatsApp — scan the QR with "
                "the phone that should send these messages")
    if http_status == 400:
        return f"bridge rejected the request (missing chatId/message): {body[:200]}"
    if http_status is None:
        return ("bridge is not reachable on localhost — start it with "
                "`node bridge.js` in the whatsapp-bridge directory")
    return f"bridge returned HTTP {http_status}: {body[:200]}"


# ─── Supabase REST helpers (no SDK dependency) ────────────────────────────────

class Supabase:
    def __init__(self, url: str, key: str) -> None:
        self.url = url.rstrip("/")
        self.key = key

    def _call(self, method: str, path: str, payload=None, prefer: str | None = None):
        req = urllib.request.Request(
            f"{self.url}/rest/v1{path}",
            method=method,
            headers={
                "apikey": self.key,
                "Authorization": f"Bearer {self.key}",
                "Content-Type": "application/json",
                **({"Prefer": prefer} if prefer else {}),
            },
            data=json.dumps(payload).encode() if payload is not None else None,
        )
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                raw = r.read().decode() or "null"
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "ignore")[:300]
            raise RuntimeError(f"supabase {method} {path} -> HTTP {e.code}: {detail}") from None

    def config(self) -> dict:
        rows = self._call(
            "GET",
            "/notification_config?select=whatsapp_provider,whatsapp_bridge_url,"
            "whatsapp_chatbot_provider,whatsapp_chatbot_bridge_url,enabled&id=eq.1",
        )
        return rows[0] if rows else {}

    def pending_bridge(self, limit: int) -> list[dict]:
        # provider=eq.bridge rather than a purpose filter: the row already records
        # which transport was chosen, and both WhatsApp numbers are served by a
        # bridge, so the ROW is the authority on whether this worker owns it.
        #
        # status=eq.pending: still queued (the edge function defers these).
        # attempts<5: mirrors the SQL cap so a poison row cannot spin forever.
        return self._call(
            "GET",
            "/notification_outbox"
            "?select=id,user_id,job_id,kind,to_address,title,body,attempts,provider,purpose"
            "&channel=eq.whatsapp&status=eq.pending&provider=eq.bridge"
            f"&attempts=lt.5&order=created_at.asc&limit={limit}",
        )

    def mark(self, outbox_id: str, status: str, error: str | None, provider: str):
        self._call(
            "POST",
            "/rpc/notification_outbox_mark",
            {
                "p_outbox_id": outbox_id,
                "p_status": status,
                "p_error": error,
                "p_provider": provider,
            },
        )

    def bump_attempts(self, outbox_id: str, attempts: int):
        # Kept separate from notification_outbox_mark (which only records terminal
        # states) so a row that keeps failing eventually falls out of the queue
        # instead of being retried forever.
        self._call(
            "PATCH",
            f"/notification_outbox?id=eq.{outbox_id}",
            {"attempts": attempts + 1},
            prefer="return=minimal",
        )


# ─── phone + bridge ──────────────────────────────────────────────────────────

def to_jid(raw: str) -> str | None:
    """Indonesian number -> WhatsApp individual JID.

    Mirrors normaliseMsisdn() in the dispatch function so both paths agree.
    Accepts 08xx, 8xx, 62xx and +62xx, plus anything already JID-shaped.
    """
    if not raw:
        return None
    s = raw.strip()
    if s.endswith("@s.whatsapp.net"):
        return s
    digits = re.sub(r"\D", "", s)
    if not digits:
        return None
    if digits.startswith("62"):
        pass
    elif digits.startswith("0"):
        digits = "62" + digits[1:]
    elif digits.startswith("8"):
        digits = "62" + digits
    return f"{digits}@s.whatsapp.net"


def send_via_bridge(bridge_url: str, row: dict) -> tuple[bool, str, bool]:
    """Returns (ok, detail, retryable).

    retryable=True means leave the row pending: either the bridge is down or it
    is up but unpaired. Both resolve on their own once an operator acts, so
    marking the row `failed` would throw away a message that could still go out.
    """
    jid = to_jid(row.get("to_address") or "")
    if not jid:
        return False, f"unusable whatsapp number: {row.get('to_address')!r}", False

    payload = {
        "chatId": jid,
        "message": f"{row.get('title', '')}\n\n{row.get('body', '')}".strip(),
    }
    req = urllib.request.Request(
        f"{bridge_url.rstrip('/')}/send",
        method="POST",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload).encode(),
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            body = r.read().decode("utf-8", "ignore")
        parsed = json.loads(body) if body.strip() else {}
        if parsed.get("success") is False:
            return False, f"bridge rejected: {body[:200]}", False
        return True, f"bridge accepted ({parsed.get('messageId', 'no id')})", False
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "ignore")
        retryable = e.code == 503
        return False, explain(e.code, detail), retryable
    except urllib.error.URLError as e:
        return False, explain(None, str(e)), True


def health(bridge_url: str) -> tuple[bool, str]:
    try:
        with urllib.request.urlopen(f"{bridge_url.rstrip('/')}/health", timeout=5) as r:
            data = json.loads(r.read().decode() or "{}")
        state = data.get("status", "unknown")
        if state == "connected":
            return True, "connected"
        return False, f"bridge up but status={state!r} (not paired)"
    except Exception as e:
        return False, explain(None, str(e))


# ─── main ────────────────────────────────────────────────────────────────────

def one_pass(sb: Supabase, bridges: dict[str, str], limit: int, dry_run: bool) -> int:
    """bridges maps purpose -> bridge base URL ('chatbot', 'notif')."""
    cfg = sb.config()
    if not cfg.get("enabled", True):
        print("notification_config.enabled = false — nothing to do")
        return 0

    # Either slot being a bridge means there may be rows for this worker. Do not
    # require a single global provider: the chatbot number and the notification
    # number are independent settings, and one can be a bridge while the other is
    # Meta (which is exactly the intended split).
    notif_is_bridge = cfg.get("whatsapp_provider") == "bridge"
    chatbot_is_bridge = cfg.get("whatsapp_chatbot_provider") == "bridge"
    if not notif_is_bridge and not chatbot_is_bridge:
        print(f"neither whatsapp_provider ({cfg.get('whatsapp_provider')!r}) nor "
              f"whatsapp_chatbot_provider ({cfg.get('whatsapp_chatbot_provider')!r}) "
              "is 'bridge' — this worker only handles bridge rows")
        return 0

    # A URL configured in the DB wins over the CLI default: the DB is the
    # deployment's record, and setting it also hands these rows to the edge
    # function instead.
    if cfg.get("whatsapp_bridge_url") or cfg.get("whatsapp_chatbot_bridge_url"):
        print("a bridge url is set in notification_config — the edge function handles "
              "those rows; clear it to use this worker")
        if not any(bridges.values()):
            return 0

    rows = sb.pending_bridge(limit)
    if not rows:
        print("no pending bridge rows")
        return 0

    # Health-check only the bridges we are about to use, so a wrong port for an
    # unused number does not block the working one.
    needed = {"chatbot" if r.get("purpose") == "chatbot" else "notif" for r in rows}
    usable: set[str] = set()
    for purpose in sorted(needed):
        url = bridges.get(purpose)
        if not url:
            print(f"[{purpose}] no bridge URL given — rows left pending "
                  f"(pass --bridge-chatbot / --bridge as appropriate)")
            continue
        ok, detail = health(url)
        print(f"[{purpose}] {url} -> {detail}")
        if ok:
            usable.add(purpose)

    sent = failed = waited = 0
    for row in rows:
        purpose = "chatbot" if row.get("purpose") == "chatbot" else "notif"
        jid = to_jid(row.get("to_address") or "")

        if purpose not in usable:
            waited += 1
            continue
        if dry_run:
            print(f"  [dry-run] {purpose}: would send kind={row['kind']} to {jid}")
            continue

        ok, detail, retryable = send_via_bridge(bridges[purpose], row)
        if ok:
            sb.mark(row["id"], "sent", None, "bridge")
            sent += 1
            print(f"  sent  [{purpose}] {row['kind']} -> {jid}")
        elif retryable:
            # Leave pending so the next run retries; only count the attempt.
            sb.bump_attempts(row["id"], row.get("attempts", 0))
            waited += 1
            print(f"  wait  [{purpose}] {row['kind']} -> {jid}: {detail}")
        else:
            sb.mark(row["id"], "failed", detail[:1000], "bridge")
            failed += 1
            print(f"  fail  [{purpose}] {row['kind']} -> {jid}: {detail}")

    print(f"pass complete: {sent} sent, {failed} failed, {waited} left pending")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--bridge",
                    default=os.environ.get("WHATSAPP_BRIDGE_URL", BRIDGE_DEFAULT),
                    help=f"NOTIFICATION-number bridge (default {BRIDGE_DEFAULT})")
    ap.add_argument("--bridge-chatbot",
                    default=os.environ.get("WHATSAPP_CHATBOT_BRIDGE_URL"),
                    help="CHATBOT-number bridge; a separate Baileys session/port. "
                         "Defaults to --bridge when not given.")
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--watch", action="store_true", help="loop forever, 60s apart")
    ap.add_argument("--interval", type=int, default=60)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 1

    bridges = {
        "notif": args.bridge or "",
        "chatbot": args.bridge_chatbot or args.bridge or "",
    }
    if bridges["chatbot"] and not args.bridge_chatbot:
        print("note: --bridge-chatbot not set; chatbot rows will use the notification "
              "bridge. Two numbers need two bridge processes on two ports.")

    sb = Supabase(url, key)
    while True:
        try:
            code = one_pass(sb, bridges, args.limit, args.dry_run)
        except RuntimeError as e:
            print(f"error: {e}", file=sys.stderr)
            code = 1
        if not args.watch:
            return code
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
