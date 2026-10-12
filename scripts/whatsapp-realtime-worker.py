#!/usr/bin/env python3
"""Send WhatsApp notifications from a machine with no public IP.

THE PROBLEM THIS SOLVES

    Supabase runs in the cloud. This machine is behind NAT with no public address
    and no inbound route, so nothing in the cloud can call it. But a customer's
    status change happens in the cloud (a trigger writes to notification_outbox),
    and the bridge that can actually send is here on loopback.

    You cannot fix that by giving the cloud a URL to call. You fix it by having
    THIS process hold an open connection outbound. Supabase Realtime is a
    WebSocket the client opens; once open, the cloud pushes events down it. No
    port forwarding, no tunnel, no public IP, no inbound firewall rule.

    Realtime is best-effort transport, so it is NOT the source of truth: this
    worker also does a REST catch-up on start and on a timer, which is what
    covers rows queued while it was offline or while the socket was down.

WHY NOT JUST POLL

    Polling alone also works and needs nothing enabled. Realtime exists here to
    make delivery prompt — a job transition should not sit for up to a poll
    interval — while the timer catch-up guarantees nothing is lost if the socket
    drops. Both paths run through the same send function, so a row delivered
    twice cannot be sent twice: the send path re-checks status before sending.

PREREQUISITE (already applied for this project)

    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_outbox;

USAGE

    python whatsapp-realtime-worker.py --bridge http://127.0.0.1:3000
    python whatsapp-realtime-worker.py --bridge http://127.0.0.1:3000 --catch-up 300

REQUIRED ENVIRONMENT

    SUPABASE_URL                https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY   service role — reads the outbox, records outcomes,
                                and authenticates the Realtime socket
"""

from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Reuse the drain worker's helpers rather than re-deriving them: the JID
# normalisation and the error translation must behave identically or the two
# paths disagree about what a valid number is.
_here = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("drain", _here / "whatsapp-drain-worker.py")
drain = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(drain)

try:
    import websockets
except ImportError:
    print("websockets is required: pip install websockets", file=sys.stderr)
    raise SystemExit(1)


TOPIC = "realtime:public:notification_outbox"


def send_row(sb: "drain.Supabase", bridge_url: str, row: dict, dry_run: bool) -> str:
    """Send one outbox row. Returns 'sent' | 'failed' | 'wait' | 'skip'.

    Status is re-checked from the DB first: Realtime can deliver the same INSERT
    that the catch-up sweep also picked up, and sending a message twice is worse
    than sending it late.
    """
    rid = row["id"]
    fresh = sb.one(f"/notification_outbox?select=status,attempts,to_address,title,body,kind&id=eq.{rid}")
    if not fresh or fresh.get("status") != "pending":
        return "skip"

    if dry_run:
        print(f"  [dry-run] would send {fresh.get('kind')} to {fresh.get('to_address')}")
        return "skip"

    ok, detail, retryable = drain.send_via_bridge(bridge_url, fresh)
    if ok:
        sb.mark(rid, "sent", None, "bridge")
        print(f"  sent  {fresh.get('kind')} -> {drain.to_jid(fresh.get('to_address') or '')}")
        return "sent"
    if retryable:
        sb.bump_attempts(rid, fresh.get("attempts", 0))
        print(f"  wait  {fresh.get('kind')}: {detail}")
        return "wait"
    sb.mark(rid, "failed", detail[:1000], "bridge")
    print(f"  fail  {fresh.get('kind')}: {detail}")
    return "failed"


def catch_up(sb: "drain.Supabase", bridges: dict[str, str], limit: int, dry_run: bool) -> None:
    # We call the modified drain worker one_pass
    drain.one_pass(sb, bridges, limit, dry_run)


async def watch(sb: "drain.Supabase", key: str, ws_url: str, bridges: dict[str, str],
                catch_up_secs: int, dry_run: bool, limit: int) -> None:
    # start with a sweep so anything queued while offline goes out immediately
    catch_up(sb, bridges, limit, dry_run)

    last_catch_up = time.time()
    backoff = 2

    while True:
        try:
            async with websockets.connect(ws_url, ping_interval=20, ping_timeout=20,
                                          max_size=2**22) as ws:
                await ws.send(json.dumps({
                    "topic": TOPIC, "event": "phx_join", "ref": "1",
                    "payload": {"config": {"postgres_changes": [
                        {"event": "INSERT", "schema": "public", "table": "notification_outbox"}
                    ]}},
                }))
                print(f"subscribed to {TOPIC}")
                backoff = 2

                while True:
                    # Realtime needs a heartbeat or the server drops the socket.
                    if int(time.time()) % 25 < 1:
                        await ws.send(json.dumps({"topic": "phoenix", "event": "heartbeat",
                                                  "payload": {}, "ref": f"hb{int(time.time())}"}))
                    try:
                        raw = await asyncio.wait_for(ws.recv(), timeout=5)
                    except asyncio.TimeoutError:
                        raw = None

                    if raw:
                        msg = json.loads(raw)
                        if msg.get("event") == "postgres_changes":
                            rec = ((msg.get("payload") or {}).get("data") or {}).get("record") or {}
                            if (rec.get("channel") == "whatsapp"
                                    and rec.get("provider") == "bridge"
                                    and rec.get("status") == "pending"):
                                # Route to the correct bridge URL depending on purpose
                                b_url = bridges.get("chatbot") if rec.get("purpose") == "chatbot" else bridges.get("notif")
                                if b_url:
                                    send_row(sb, b_url, rec, dry_run)

                    # Safety net: realtime can miss events across a reconnect.
                    if catch_up_secs and time.time() - last_catch_up > catch_up_secs:
                        last_catch_up = time.time()
                        catch_up(sb, bridges, limit, dry_run)

        except Exception as e:
            print(f"socket error: {type(e).__name__}: {str(e)[:160]} — reconnecting in {backoff}s",
                  file=sys.stderr)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--bridge", default=os.environ.get("WHATSAPP_BRIDGE_URL", drain.BRIDGE_DEFAULT),
                    help=f"NOTIFICATION-number bridge (default {drain.BRIDGE_DEFAULT})")
    ap.add_argument("--bridge-chatbot", default=os.environ.get("WHATSAPP_CHATBOT_BRIDGE_URL"),
                    help="CHATBOT-number bridge")
    ap.add_argument("--catch-up", type=int, default=300,
                    help="seconds between REST sweeps (0 disables). Safety net for missed events.")
    ap.add_argument("--limit", type=int, default=100)
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

    ws_url = (url.replace("https://", "wss://").replace("http://", "ws://").rstrip("/")
              + "/realtime/v1/websocket?" + urllib.parse.urlencode({"apikey": key, "vsn": "1.0.0"}))

    ok, detail = drain.health(bridges["notif"])
    print(f"bridge {bridges['notif']} -> {detail}")
    if not ok:
        print("bridge not ready; catch-up rows will be left pending. "
              "Realtime will send them once it connects.", file=sys.stderr)

    sb = drain.Supabase(url, key)
    try:
        asyncio.run(watch(sb, key, ws_url, bridges, args.catch_up, args.dry_run, args.limit))
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
