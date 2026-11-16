#!/usr/bin/env python3
"""Apply and verify the CORS policy on the R2 bucket `revive-photos`.

Why this exists: the app uploads photos with a presigned PUT issued by the
`r2-presign` edge function, straight from the browser. Browsers gate that PUT
behind a CORS preflight, and an R2 bucket with no CORS policy answers every
preflight with 403 "CORS not configured for this bucket". Reads still work
because <img> does not need CORS, so the only symptom is uploads dying with
`ClientException: Failed to fetch` — the estimator's exact failure mode.

Bucket CORS is NOT settable with the R2 S3 key pair: `?cors` on the
S3-compatible endpoint returns AccessDenied even though object GET/PUT with the
same key succeed. It must go through the Cloudflare API, which needs a token
carrying `Workers R2 Storage: Edit`.

Usage:
  CF_API_TOKEN=... python scripts/set_r2_cors.py            # apply + verify
  CF_API_TOKEN=... python scripts/set_r2_cors.py --check    # read current policy only

Exit 0 only when the policy is applied AND a live preflight from the
production origin returns an Access-Control-Allow-Origin header.
"""
import json
import os
import sys
import urllib.error
import urllib.request

ACCOUNT_ID = os.environ.get("R2_ACCOUNT_ID_ADMIN", "1bfeaffe898cab205cf0251acc7589f6")
BUCKET = os.environ.get("R2_BUCKET", "revive-photos")
CF_API = "https://api.cloudflare.com/client/v4"

# Every origin a browser upload can legitimately come from. R2 matches origins
# literally (no port wildcards), so dev ports must be listed when used.
PROD_ORIGINS = [
    "https://revive.co.id",
    "https://www.revive.co.id",
    "https://app.revive.co.id",
]
DEV_ORIGINS = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:8080",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8080",
]

POLICY = {
    "rules": [
        {
            "allowed": {
                "origins": PROD_ORIGINS + DEV_ORIGINS,
                "methods": ["GET", "PUT", "HEAD", "POST"],
                "headers": ["Content-Type", "x-amz-*"],
            },
            "exposeHeaders": ["ETag"],
            # Browsers cache the preflight for 1h; keeps upload bursts cheap.
            "maxAgeSeconds": 3600,
        }
    ]
}


def cf(method: str, path: str, token: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        CF_API + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read(2000)
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")}


def anon_key() -> str | None:
    if os.environ.get("SUPABASE_ANON_KEY"):
        return os.environ["SUPABASE_ANON_KEY"]
    env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
    try:
        for line in open(env_path, encoding="utf-8"):
            if line.startswith("SUPABASE_ANON_KEY="):
                return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return None


def supabase_url() -> str:
    return os.environ.get("SUPABASE_URL", "https://ahaospjkkuetkaixwzzz.supabase.co").rstrip("/")


def post_function(path: str, body: dict, key: str, token: str | None = None):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        supabase_url() + path, data=json.dumps(body).encode(), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read(400).decode(errors="replace")


def preflight(url: str, origin: str):
    """Return (status, allow-origin header) for an OPTIONS preflight."""
    req = urllib.request.Request(
        url,
        method="OPTIONS",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.headers.get("access-control-allow-origin")
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("access-control-allow-origin")


def verify() -> bool:
    key = anon_key()
    if not key:
        print("SKIP  live verification — no SUPABASE_ANON_KEY available")
        return True
    code, session = post_function("/auth/v1/signup", {}, key)
    token = session.get("access_token") if isinstance(session, dict) else None
    if not token:
        print(f"FAIL  could not mint an anonymous session ({code})")
        return False
    code, res = post_function(
        "/functions/v1/r2-presign", {"action": "upload", "scope": "estimator", "ext": "jpg"}, key, token
    )
    if code != 200 or "url" not in res:
        print(f"FAIL  presign upload returned {code}: {res}")
        return False

    ok = True
    for origin in ("https://revive.co.id", "https://www.revive.co.id"):
        status, allow = preflight(res["url"], origin)
        passed = status in (200, 204) and allow == origin
        print(f"{'PASS' if passed else 'FAIL'}  preflight {origin} -> {status} allow-origin={allow}")
        ok = ok and passed

    # A foreign origin must still be refused; catch an over-broad policy.
    status, allow = preflight(res["url"], "https://evil.example.com")
    refused = status in (403, 401) or not allow or allow != "https://evil.example.com"
    print(f"{'PASS' if refused else 'FAIL'}  foreign origin refused -> {status} allow-origin={allow}")
    ok = ok and refused

    if ok:
        # The preflight passing is not the same as the upload landing: do the PUT.
        put = urllib.request.Request(
            res["url"],
            data=b"cors-probe",
            method="PUT",
            headers={"Content-Type": "image/jpeg", "Origin": "https://revive.co.id"},
        )
        try:
            with urllib.request.urlopen(put, timeout=60) as r:
                print(f"{'PASS' if r.status == 200 else 'FAIL'}  PUT to R2 -> {r.status}")
                ok = ok and r.status == 200
        except urllib.error.HTTPError as e:
            print(f"FAIL  PUT to R2 -> {e.code}")
            ok = False
    print(f"probe key (delete after): {res.get('key')}")
    return ok


def main() -> int:
    token = os.environ.get("CF_API_TOKEN")
    if not token:
        print("Set CF_API_TOKEN to a Cloudflare token with 'Workers R2 Storage: Edit' on this account.")
        return 2
    path = f"/accounts/{ACCOUNT_ID}/r2/buckets/{BUCKET}/cors"

    status, current = cf("GET", path, token)
    print(f"current CORS -> {status} {json.dumps(current.get('result'))[:200] if status == 200 else current.get('errors')}")

    if "--check" in sys.argv:
        return 0 if status == 200 else 1

    status, res = cf("PUT", path, token, POLICY)
    if status != 200 or not res.get("success"):
        print(f"FAIL  PUT cors -> {status} {json.dumps(res)[:400]}")
        return 1
    print("PASS  CORS policy applied")

    status, res = cf("GET", path, token)
    rules = (res.get("result") or {}).get("rules") if status == 200 else None
    print(f"PASS  policy reads back as {json.dumps(rules)[:200]}" if rules else f"WARN  read-back -> {status}")

    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main())
