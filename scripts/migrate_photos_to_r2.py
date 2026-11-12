#!/usr/bin/env python3
"""
Copy every object in Supabase bucket `revive-photos` to the R2 bucket of the
same name, keeping object keys identical so database rows need no changes.

Stdlib only. Credentials come from the environment:
  SUPABASE_URL                 e.g. https://<ref>.supabase.co
  SUPABASE_SERVICE_ROLE_KEY    service role key (bypasses storage RLS)
  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET

Usage:
  python scripts/migrate_photos_to_r2.py            # dry run, lists only
  python scripts/migrate_photos_to_r2.py --copy     # copies objects missing in R2

Idempotent: objects that already exist in R2 with the same size are skipped.
"""
import datetime
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
R2_ACCOUNT_ID = os.environ["R2_ACCOUNT_ID"]
R2_ACCESS_KEY_ID = os.environ["R2_ACCESS_KEY_ID"]
R2_SECRET_ACCESS_KEY = os.environ["R2_SECRET_ACCESS_KEY"]
R2_BUCKET = os.environ.get("R2_BUCKET", "revive-photos")
SOURCE_BUCKET = "revive-photos"

R2_HOST = f"{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
REGION = "auto"
SERVICE = "s3"


# ---------- Supabase storage ----------

def sb_request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{SUPABASE_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {SERVICE_KEY}",
            "apikey": SERVICE_KEY,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def list_folder(prefix):
    """Return (files, subfolders) directly under prefix, paging through results."""
    files, folders = [], []
    offset = 0
    while True:
        page = json.loads(sb_request(
            "POST",
            f"/storage/v1/object/list/{SOURCE_BUCKET}",
            {"prefix": prefix, "limit": 1000, "offset": offset,
             "sortBy": {"column": "name", "order": "asc"}},
        ))
        if not page:
            break
        for item in page:
            full = f"{prefix}{item['name']}"
            # Folders come back with id = null.
            if item.get("id") is None:
                folders.append(full + "/")
            else:
                meta = item.get("metadata") or {}
                files.append({
                    "key": full,
                    "size": meta.get("size"),
                    "mimetype": meta.get("mimetype") or "application/octet-stream",
                })
        if len(page) < 1000:
            break
        offset += 1000
    return files, folders


def list_all_objects():
    """Walk the whole bucket breadth-first."""
    all_files = []
    queue = [""]
    while queue:
        prefix = queue.pop()
        files, folders = list_folder(prefix)
        all_files.extend(files)
        queue.extend(folders)
    return all_files


def download(key):
    quoted = urllib.parse.quote(key, safe="/")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/storage/v1/object/{SOURCE_BUCKET}/{quoted}",
        headers={"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


# ---------- R2 (S3 SigV4) ----------

def _sign(key, msg):
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def r2_request(method, key, body=b"", extra_headers=None, query=""):
    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(body).hexdigest()

    canonical_uri = "/" + R2_BUCKET + ("/" + urllib.parse.quote(key, safe="/") if key else "")
    headers = {
        "host": R2_HOST,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }
    if extra_headers:
        headers.update({k.lower(): v for k, v in extra_headers.items()})
    signed = ";".join(sorted(headers))
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in sorted(headers))
    canonical_request = "\n".join([
        method, canonical_uri, query, canonical_headers, signed, payload_hash,
    ])
    scope = f"{date_stamp}/{REGION}/{SERVICE}/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256", amz_date, scope,
        hashlib.sha256(canonical_request.encode()).hexdigest(),
    ])
    k = _sign(("AWS4" + R2_SECRET_ACCESS_KEY).encode(), date_stamp)
    k = _sign(k, REGION)
    k = _sign(k, SERVICE)
    k = _sign(k, "aws4_request")
    signature = hmac.new(k, string_to_sign.encode(), hashlib.sha256).hexdigest()

    auth = (f"AWS4-HMAC-SHA256 Credential={R2_ACCESS_KEY_ID}/{scope}, "
            f"SignedHeaders={signed}, Signature={signature}")
    send = {
        "x-amz-date": amz_date,
        "x-amz-content-sha256": payload_hash,
        "Authorization": auth,
    }
    if extra_headers:
        send.update(extra_headers)
    url = f"https://{R2_HOST}{canonical_uri}" + (f"?{query}" if query else "")
    req = urllib.request.Request(url, data=body if method == "PUT" else None,
                                 method=method, headers=send)
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.status, r.read()


def r2_head_size(key):
    """Return the object's size in R2, or None if it doesn't exist."""
    try:
        now = datetime.datetime.now(datetime.timezone.utc)
        # HEAD via the same signer; reuse r2_request with a HEAD method.
        url_key = key
        status, _ = r2_request("HEAD", url_key)
        return status
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


# ---------- main ----------

def main():
    copy = "--copy" in sys.argv
    objects = list_all_objects()
    total = sum(o["size"] or 0 for o in objects)
    print(f"source objects: {len(objects)}  ({total / 1024 / 1024:.1f} MB)")
    if not copy:
        for o in objects:
            print(f"  {o['key']}  {o['size']}  {o['mimetype']}")
        print("dry run only. re-run with --copy to upload.")
        return

    copied = skipped = failed = 0
    for o in objects:
        key = o["key"]
        try:
            # Skip objects already present in R2 (HEAD returns 200).
            try:
                r2_request("HEAD", key)
                skipped += 1
                continue
            except urllib.error.HTTPError as e:
                if e.code != 404:
                    raise
            data = download(key)
            r2_request("PUT", key, body=data,
                       extra_headers={"content-type": o["mimetype"]})
            copied += 1
            print(f"copied  {key}  ({len(data)} bytes)")
        except Exception as e:  # keep going, report at the end
            failed += 1
            print(f"FAILED  {key}  {e}")

    print(f"done: copied={copied} skipped={skipped} failed={failed}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
