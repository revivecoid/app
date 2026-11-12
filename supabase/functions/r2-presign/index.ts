import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";

// Issues short-lived presigned URLs for the R2 bucket. The Flutter app never
// sees R2 credentials. Keys are generated here, always under the caller's uid.

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID") ?? "";
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID") ?? "";
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "";
const R2_BUCKET = Deno.env.get("R2_BUCKET") ?? "revive-photos";

const REGION = "auto";
const SERVICE = "s3";
const PRESIGN_TTL_SECONDS = 300;

// Upload scopes. The function derives the whole key, so a caller can only write
// into the folders its scope allows — never outside them.
const PARTNER_SCOPES: Record<string, (p: string) => string> = {
  partnerDocs: (p) => `partners/${p}/docs`,
  partnerFacility: (p) => `partners/${p}/facility`,
};

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Read rule, matching the SEC-05 policies: own folder, master admin, or a member
// of the partner that owns the path. Checks run as the caller through the same
// SQL helpers the RLS policies use, so the DB stays the source of truth.
const PARTNER_PREFIXES = new Set(["facility", "partners", "ops"]);
const PARTNER_ROLES = ["owner", "mechanic"];

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

// Runs as the caller so memberships and is_master_admin() see auth.uid().
function asCaller(token: string) {
  return createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

async function isMemberOf(token: string, partnerId: string): Promise<boolean> {
  const client = asCaller(token);
  const { data: isAdmin } = await client.rpc("is_master_admin");
  if (isAdmin === true) return true;
  const { data, error } = await client.rpc("has_partner_membership", {
    p_org_id: partnerId,
    p_roles: ["owner", "mechanic", "staff"],
  });
  return !error && data === true;
}

async function canRead(token: string, uid: string, key: string): Promise<boolean> {
  if (key.startsWith(`${uid}/`)) return true;

  const userClient = asCaller(token);

  const { data: isAdmin, error: adminErr } = await userClient.rpc("is_master_admin");
  if (!adminErr && isAdmin === true) return true;

  const [prefix, partnerId] = key.split("/");
  if (PARTNER_PREFIXES.has(prefix) && isUuid(partnerId ?? "")) {
    // Parameter names must match the SQL signature: (p_org_id, p_roles).
    const { data, error } = await userClient.rpc("has_partner_membership", {
      p_org_id: partnerId,
      p_roles: PARTNER_ROLES,
    });
    return !error && data === true;
  }
  return false;
}

const ALLOWED_ORIGINS = new Set([
  "https://revive.co.id",
  "https://app.revive.co.id",
  "http://localhost:3000",
  "http://localhost",
]);

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://revive.co.id";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

const enc = new TextEncoder();

// S3 ListObjectsV2, signed with the service credentials. Only reachable by a
// master admin (checked in the request handler), because it exposes every key.
async function listObjects(prefix: string, limit: number): Promise<unknown[]> {
  const host = `${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const scope = `${dateStamp}/${REGION}/${SERVICE}/aws4_request`;
  const payloadHash = await sha256Hex("");

  const params: [string, string][] = [
    ["list-type", "2"],
    ["max-keys", String(limit)],
  ];
  if (prefix) params.push(["prefix", prefix]);
  params.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const canonicalQuery = params
    .map(([k, v]) => `${encodeRfc3986(k)}=${encodeRfc3986(v)}`)
    .join("&");

  const canonicalUri = "/" + encodeRfc3986(R2_BUCKET);
  const canonicalHeaders =
    `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

  const canonicalRequest = [
    "GET",
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");

  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const kDate = await hmac(enc.encode("AWS4" + R2_SECRET_ACCESS_KEY), dateStamp);
  const kRegion = await hmac(kDate, REGION);
  const kService = await hmac(kRegion, SERVICE);
  const kSigning = await hmac(kService, "aws4_request");
  const signature = hex(await hmac(kSigning, stringToSign));

  const url = `https://${host}${canonicalUri}?${canonicalQuery}`;
  const res = await fetch(url, {
    headers: {
      "x-amz-content-sha256": payloadHash,
      "x-amz-date": amzDate,
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${R2_ACCESS_KEY_ID}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
  });
  if (!res.ok) throw new Error(`R2 list failed: ${res.status}`);

  const xml = await res.text();
  const items: unknown[] = [];
  for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
    const body = m[1];
    const pick = (tag: string) => {
      const hit = body.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
      return hit ? hit[1] : "";
    };
    items.push({
      key: pick("Key"),
      size: Number(pick("Size") || 0),
      last_modified: pick("LastModified"),
    });
  }
  return items;
}

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(data: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(data)));
}

async function hmac(key: BufferSource, data: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", k, enc.encode(data));
}

// RFC 3986 encoding, applied per path segment so slashes survive.
function encodeRfc3986(s: string): string {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) =>
    "%" + c.charCodeAt(0).toString(16).toUpperCase()
  );
}

async function presign(method: "GET" | "PUT", key: string): Promise<string> {
  const host = `${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const scope = `${dateStamp}/${REGION}/${SERVICE}/aws4_request`;

  const canonicalUri = "/" + [R2_BUCKET, ...key.split("/")].map(encodeRfc3986).join("/");

  const params: [string, string][] = [
    ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
    ["X-Amz-Credential", `${R2_ACCESS_KEY_ID}/${scope}`],
    ["X-Amz-Date", amzDate],
    ["X-Amz-Expires", String(PRESIGN_TTL_SECONDS)],
    ["X-Amz-SignedHeaders", "host"],
  ];
  params.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const canonicalQuery = params
    .map(([k, v]) => `${encodeRfc3986(k)}=${encodeRfc3986(v)}`)
    .join("&");

  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    `host:${host}\n`,
    "host",
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const kDate = await hmac(enc.encode("AWS4" + R2_SECRET_ACCESS_KEY), dateStamp);
  const kRegion = await hmac(kDate, REGION);
  const kService = await hmac(kRegion, SERVICE);
  const kSigning = await hmac(kService, "aws4_request");
  const signature = hex(await hmac(kSigning, stringToSign));

  return `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

serve(async (req) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, origin);
  }

  if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY) {
    return json({ error: "R2 is not configured" }, 500, origin);
  }

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) {
    return json({ error: "Unauthorized" }, 401, origin);
  }
  const uid = userData.user.id;

  let body: {
    action?: string;
    scope?: string;
    key?: string;
    ext?: string;
    partner_id?: string;
    job_id?: string;
    stage_key?: string;
    doc_type?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, origin);
  }

  if (body.action === "upload") {
    const ext = (body.ext ?? "jpg").toLowerCase();
    if (!/^[a-z0-9]{2,5}$/.test(ext)) {
      return json({ error: "Invalid extension" }, 400, origin);
    }
    const stamp = Date.now();
    const rand = crypto.randomUUID();
    let dir: string;

    switch (body.scope) {
      case "learning":
      case "estimator":
      case "self":
        dir = body.scope === "self" ? `${uid}` : `${uid}/${body.scope}`;
        break;
      case "opsJob": {
        const partnerId = body.partner_id ?? "";
        const jobId = body.job_id ?? "";
        const stageKey = body.stage_key ?? "";
        if (!isUuid(partnerId) || !isUuid(jobId) || !/^[a-z0-9_]{2,40}$/.test(stageKey)) {
          return json({ error: "Invalid ops job scope" }, 400, origin);
        }
        dir = `ops/${partnerId}/${jobId}/${stageKey}`;
        break;
      }
      case "partnerDocs":
      case "partnerFacility": {
        const partnerId = body.partner_id ?? "";
        if (!isUuid(partnerId)) {
          return json({ error: "Invalid partner" }, 400, origin);
        }
        const allowed = await isMemberOf(token, partnerId);
        if (!allowed) return json({ error: "Forbidden" }, 403, origin);
        dir = PARTNER_SCOPES[body.scope](partnerId);
        if (body.scope === "partnerDocs") {
          const docType = body.doc_type ?? "";
          if (!/^[a-z0-9_]{2,20}$/.test(docType)) {
            return json({ error: "Invalid doc type" }, 400, origin);
          }
          dir = `${dir}/${docType}`;
        }
        break;
      }
      default:
        return json({ error: "Invalid scope" }, 400, origin);
    }

    const key = `${dir}/${stamp}_${rand}.${ext}`;
    const url = await presign("PUT", key);
    return json({ key, url, expiresIn: PRESIGN_TTL_SECONDS }, 200, origin);
  }

  if (body.action === "read") {
    const key = body.key ?? "";
    if (key.includes("..") || !(await canRead(token, uid, key))) {
      return json({ error: "Forbidden" }, 403, origin);
    }
    const url = await presign("GET", key);
    return json({ key, url, expiresIn: PRESIGN_TTL_SECONDS }, 200, origin);
  }

  if (body.action === "list") {
    // Admin-only: the bucket listing exposes every key.
    const { data: isAdmin, error: adminErr } = await asCaller(token).rpc("is_master_admin");
    if (adminErr || isAdmin !== true) {
      return json({ error: "Forbidden" }, 403, origin);
    }
    const prefix = (body as { prefix?: string }).prefix ?? "";
    if (prefix.includes("..")) {
      return json({ error: "Invalid prefix" }, 400, origin);
    }
    try {
      const items = await listObjects(prefix, 200);
      return json({ items }, 200, origin);
    } catch (e) {
      return json({ error: (e as Error).message }, 502, origin);
    }
  }

  return json({ error: "Unknown action" }, 400, origin);
});
