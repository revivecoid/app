import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
// PERF-09 FIX: Use standard library base64 encoder instead of byte-by-byte loop
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64.ts";
// Business rules applied after the model answers (replace-only, quarter panel)
import {
  applyEstimatorPolicies,
  REPLACE_ONLY_DAMAGE_TYPES,
  REPLACE_ONLY_SEVERITIES,
} from "../_shared/repair_policy.ts";
// Few-shot context from finished jobs + reviewer rejections (no model training)
import {
  buildTrainingContext,
  extractPhotoKeys,
  type PanelCorrection,
  type TrainingCase,
} from "../_shared/training_context.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const googleApiKey = Deno.env.get("GOOGLE_AI_API_KEY") ?? "";
const groqApiKey = Deno.env.get("GROQ_API_KEY") ?? "";
const openaiApiKey = Deno.env.get("OPENAI_API_KEY") ?? "";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// SEC-03 FIX: Lock CORS to production domain only (exact match — no startsWith)
const ALLOWED_ORIGINS = new Set(["https://revive.co.id", "https://app.revive.co.id", "http://localhost:3000", "http://localhost"]);

function getCorsHeaders(origin?: string | null): Record<string, string> {
  const allowedOrigin = (origin && ALLOWED_ORIGINS.has(origin)) ? origin : "https://revive.co.id";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

// B-09 fix: DB-backed rate limit replaces in-memory map (per isolate, bypassable)
// Called via supabase service role after JWT verification
async function checkDbRateLimit(supabaseAdmin: any, userId: string, isAnon: boolean): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc('check_ai_rate_limit', {
    p_user_id: userId,
    p_is_anon: isAnon,
  });
  if (error) {
    console.error('[RateLimit] DB check failed:', error.message, '— fail-open');
    return true; // fail-open: don't block on DB error
  }
  return data === true;
}

// SEC-03 FIX: Only accept signed URLs from our own Supabase project or the
// R2 bucket that now stores every photo. Both are presigned, short-lived URLs.
const ownSupabaseHost = new URL(supabaseUrl || "https://ahaospjkkuetkaixwzzz.supabase.co").hostname;
const r2Host = `${Deno.env.get("R2_ACCOUNT_ID") ?? ""}.r2.cloudflarestorage.com`;
function isValidPhotoUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.hostname === ownSupabaseHost ||
      parsed.hostname === "localhost" ||
      (r2Host.startsWith(".") ? false : parsed.hostname === r2Host);
  } catch {
    return false;
  }
}

// ── Hardcoded fallback prices (used if pricing_rules table is empty/unreachable) ──
const FALLBACK_PRICES: Record<string, number> = {
  'Bumper Depan': 500500,
  'Spoiler Bumper depan': 286000,
  'Kap Mesin': 715000,
  'Bumper Belakang': 500500,
  'Spoiler Bumper Belakang': 286000,
  'Bagasi': 643500,
  'Spoiler Bagasi': 286000,
  'Fender RH': 572000,
  'Pintu Depan RH': 572000,
  'Spion RH': 143000,
  'Pintu Belakang RH': 572000,
  'Quarter RH': 572000,
  'Trisplang RH': 357500,
  'Side Roof RH': 357500,
  'Fender LH': 572000,
  'Pintu Depan LH': 572000,
  'Spion LH': 143000,
  'Pintu Belakang LH': 572000,
  'Quarter LH': 572000,
  'Trisplang LH': 357500,
  'Side Roof LH': 357500,
  'Roof': 1001000,
  'Cover': 286000,
  'Bullhead': 350000,
  'Apron RH': 350000,
  'Apron LH': 350000,
  'Chasis RH': 500000,
  'Chasis LH': 500000,
  'Engsel Kap Mesin RH': 100000,
  'Engsel Kap Mesin LH': 100000,
  'Panel Cowl Kaca Depan': 300000,
  'B/P Kaca Depan': 250000,
  'B/P Radiator & AC Pack': 150000,
  'Isi Freon AC': 300000,
};

// ── LivePricingRule: shape of a row from the pricing_rules table ──
interface LivePricingRule {
  panel_name: string;   // matches what AI returns and what's in DB
  base_rate: number;
  severity_min: number; // sedang (medium) multiplier
  severity_max: number; // berat  (heavy)  multiplier
}

// ── Few-shot context: finished jobs (ai_training_context) + reviewer rejections ──
interface TrainingContextLoad {
  text: string;
  usedCaseIds: string[];
  usedCorrections: number;
}

async function loadTrainingContext(terms: string[]): Promise<TrainingContextLoad> {
  try {
    const [casesRes, correctionsRes] = await Promise.all([
      supabase
        .from("ai_training_context")
        .select("id, car_make_model, damage_description, resolved_actual_cost, created_at")
        .eq("is_active_context", true)
        .order("created_at", { ascending: false })
        .limit(50),
      supabase
        .from("ai_learning_panel_reviews")
        .select("panel_name, ai_severity, comment")
        .eq("verdict", false)
        .order("created_at", { ascending: false })
        .limit(10),
    ]);

    if (casesRes.error) {
      console.warn("[vision-estimation] ai_training_context fetch failed:", casesRes.error.message);
    }
    if (correctionsRes.error) {
      console.warn("[vision-estimation] panel review fetch failed:", correctionsRes.error.message);
    }

    const context = buildTrainingContext({
      cases: (casesRes.data ?? []) as TrainingCase[],
      corrections: (correctionsRes.data ?? []) as PanelCorrection[],
      terms,
    });
    return {
      text: context.text,
      usedCaseIds: context.usedCaseIds,
      usedCorrections: context.usedCorrections,
    };
  } catch (err) {
    // Context is an enhancement: never fail an estimate because of it.
    console.warn("[vision-estimation] few-shot context skipped:", err);
    return { text: "", usedCaseIds: [], usedCorrections: 0 };
  }
}

// ── Fetches live pricing rules from DB; gracefully falls back to hardcoded map ──
async function loadPricingRules(): Promise<LivePricingRule[]> {
  try {
    const { data, error } = await supabase
      .from("pricing_rules")
      .select("panel_name, base_rate, severity_min, severity_max");

    if (error || !data || data.length === 0) {
      console.warn("pricing_rules fetch failed or empty — using hardcoded fallback.", error?.message);
      return Object.entries(FALLBACK_PRICES).map(([panel_name, base_rate]) => ({
        panel_name,
        base_rate,
        severity_min: 1.5,
        severity_max: 2.0,
      }));
    }
    return data as LivePricingRule[];
  } catch (err) {
    console.error("Unexpected error loading pricing_rules:", err);
    return Object.entries(FALLBACK_PRICES).map(([panel_name, base_rate]) => ({
      panel_name,
      base_rate,
      severity_min: 1.5,
      severity_max: 2.0,
    }));
  }
}

// ── Deterministic cost engine — uses live DB rules, not hardcoded map ──
interface CostResult {
  total: number;
  /** Derived policy items that have no pricing_rules row yet. */
  pendingPricing: string[];
}

function calculateDeterministicCost(
  structuredData: any,
  rules: LivePricingRule[]
): CostResult {
  if (!structuredData?.assessment?.damaged_panels_detail) {
    return { total: 0, pendingPricing: [] };
  }

  // L-10 fix: closed severity list — unknown value = berat (fail-safe, not ringan)
  const VALID_SEVERITIES = new Set(['ringan', 'sedang', 'berat']);

  // Build lookup map (case-insensitive handled at query time)
  const ruleMap = new Map<string, LivePricingRule>(rules.map((r) => [r.panel_name, r]));

  // C-34 fix: dedup panels by name, keep highest severity
  const panelMap = new Map<string, { severity: string; panel: any }>();
  for (const panel of structuredData.assessment.damaged_panels_detail) {
    const name: string = (panel.panel_name ?? '').trim();
    if (!name) continue;
    const rawSev: string = (panel.panel_severity ?? '').toLowerCase().trim();
    // L-10: unknown severity → berat (safe default, not ringan)
    const severity = VALID_SEVERITIES.has(rawSev) ? rawSev : 'berat';
    const existing = panelMap.get(name);
    // Keep highest severity (berat > sedang > ringan)
    const sevRank = (s: string) => s === 'berat' ? 2 : s === 'sedang' ? 1 : 0;
    if (!existing || sevRank(severity) > sevRank(existing.severity)) {
      panelMap.set(name, { severity, panel: { ...panel, panel_severity: severity } });
    }
  }

  let totalCost = 0;
  const pendingPricing: string[] = [];
  for (const [name, { severity, panel }] of panelMap) {
    // C-34 fix: case-insensitive lookup via normalized name
    const normName = name.toLowerCase();
    const rule = [...ruleMap.entries()].find(([k]) => k.toLowerCase() === normName)?.[1];
    const isDerivedItem = panel.derived === true;
    // A derived labour line with no rule (or a zero placeholder price) stays on
    // the estimate unpriced: never silently dropped, never shown as Rp0.
    if (!rule || (isDerivedItem && rule.base_rate <= 0)) {
      if (isDerivedItem) {
        // Derived policy items (quarter-replacement labour/paint) stay on the
        // estimate with cost 0 until a pricing_rules row exists for the exact
        // name. Dropping them would hide mandatory work from the customer.
        panel.calculated_cost = 0;
        panel.pricing_pending = true;
        pendingPricing.push(name);
        const derivedOrig = structuredData.assessment.damaged_panels_detail.find(
          (p: any) => (p.panel_name ?? '').trim().toLowerCase() === normName
        );
        if (derivedOrig) {
          derivedOrig.calculated_cost = 0;
          derivedOrig.pricing_pending = true;
        }
        continue;
      }
      // Unknown panel — skip with log, no fallback price (C-34: don't price silently)
      console.warn(`[pricing] Unknown panel skipped: "${name}"`);
      continue;
    }

    // Labour/paint lines added by policy are flat: the workshop sets the price
    // directly, with no severity multiplier stacked on top.
    let multiplier = 1.0;
    if (panel.derived !== true) {
      if (severity === 'sedang') multiplier = rule?.severity_min ?? 1.5;
      else if (severity === 'berat') multiplier = rule?.severity_max ?? 2.0;
    }

    const panelCost = Math.round(rule.base_rate * multiplier);
    panel.calculated_cost = panelCost;
    panel.applied_multiplier = multiplier;
    totalCost += panelCost;
    // Propagate cost back to the original panel object in structuredData
    const origPanel = structuredData.assessment.damaged_panels_detail.find(
      (p: any) => (p.panel_name ?? '').trim().toLowerCase() === normName
    );
    if (origPanel) {
      origPanel.calculated_cost = panelCost;
      origPanel.applied_multiplier = multiplier;
      origPanel.panel_severity = severity;
      if (panel.pricing_pending === true) origPanel.pricing_pending = true;
    }
  }
  return { total: totalCost, pendingPricing };
}



serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── SEC-03 FIX: Require valid JWT authentication ──────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid Authorization header" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // Verify the JWT using the anon key client (validates token signature)
    const userClient = createClient(supabaseUrl, supabaseAnonKey);
    const { data: { user }, error: authError } = await userClient.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // B-09 fix: DB-backed rate limit (persistent across isolate restarts)
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const isAnon = user.is_anonymous === true;
    if (!await checkDbRateLimit(supabaseAdmin, user.id, isAnon)) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again tomorrow.", code: "RATE_LIMITED" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 429,
      });
    }

    // damageDescription is part of the documented request contract but the
    // model derives description from the images; kept destructured so callers
    // sending it do not silently break.
    // deno-lint-ignore no-unused-vars
    const { photoUrl, photoUrls: photoUrlsRaw, damageDescription, selectedPanels } = await req.json();

    // Support both the new array format and the legacy single-URL format
    const photoUrls: string[] = Array.isArray(photoUrlsRaw) && photoUrlsRaw.length > 0
      ? photoUrlsRaw
      : photoUrl
      ? [photoUrl]
      : [];

    if (photoUrls.length === 0) {
      return new Response(JSON.stringify({ error: "photoUrl or photoUrls is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // SEC-03 FIX: Cap number of images to prevent abuse
    if (photoUrls.length > 5) {
      return new Response(JSON.stringify({ error: "Maximum 5 images allowed" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // SEC-03 FIX: Validate all URLs belong to our Supabase Storage domain
    for (const url of photoUrls) {
      if (!isValidPhotoUrl(url)) {
        return new Response(JSON.stringify({ error: `Invalid photo URL domain: ${new URL(url).hostname}` }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        });
      }
    }

    // Load AI config, live pricing rules and the few-shot context in parallel
    // for minimum latency
    const trainingTerms: string[] = Array.isArray(selectedPanels)
      ? selectedPanels.map((p: unknown) => String(p))
      : [];
    const [
      { data: configs, error: configError },
      liveRules,
      training,
    ] = await Promise.all([
      supabase
        .from("ai_config")
        .select("*")
        .eq("is_active", true)
        .order("priority_order", { ascending: true }),
      loadPricingRules(),
      loadTrainingContext(trainingTerms),
    ]);

    if (configError || !configs || configs.length === 0) {
      throw new Error("Failed to load active AI configuration (No active models found)");
    }

    const panelsConstraint = (selectedPanels && selectedPanels.length > 0)
        ? `\nIMPORTANT: The user has reported possible damage on these panels: [${selectedPanels.join(', ')}]. Use this as a HINT of which areas to inspect closely. However, you must ONLY include a panel in your response if you can VISUALLY CONFIRM actual damage (scratches, dents, deformation, or paint damage) on it from the image. If a listed panel shows NO visible damage in the image, you MUST OMIT it from damaged_panels_detail entirely. Do NOT assign default or assumed severity to panels that are not clearly damaged in the image. Accuracy is critical — do not include unverifiable panels.`
        : "";

    const masterPrompt = `You are an expert automotive loss adjuster and body repair estimator. Analyze the vehicle damage from these images thoroughly, inspecting both exterior panels and visible underlying structure/components.

1. REPAIR & LABOR ITEMS (Jasa Perbaikan):
List all damaged panels, deformed structural sections, and necessary disassembly/service operations.
Valid panel & repair item names are:
- Exterior panels: Bumper Depan, Spoiler Bumper depan, Kap Mesin, Bumper Belakang, Spoiler Bumper Belakang, Bagasi, Spoiler Bagasi, Fender RH, Pintu Depan RH, Spion RH, Pintu Belakang RH, Quarter RH, Trisplang RH, Side Roof RH, Fender LH, Pintu Depan LH, Spion LH, Pintu Belakang LH, Quarter LH, Trisplang LH, Side Roof LH, Roof, Cover.
- Inner & structural frame: Bullhead, Apron RH, Apron LH, Chasis RH, Chasis LH, Engsel Kap Mesin RH, Engsel Kap Mesin LH, Panel Cowl Kaca Depan.
- Labor/assembly operations: B/P Kaca Depan (if windshield broken/dislodged), B/P Radiator & AC Pack (if frontal crash impacted cooling/radiator area), Isi Freon AC (if AC condenser damaged/discharged).${panelsConstraint}

For each repair item, classify panel_severity into 'ringan', 'sedang', or 'berat'. Specify damage_type ('scratch', 'dent', or 'broken').
Set requires_replacement to true if the panel/component is severely deformed/crushed and cannot be economically repaired by hammer/straightening.

REPAIR POLICY (mandatory):
- Severe deformation (panel_severity 'berat' with damage_type 'dent') or any broken/cracked/punctured part (damage_type 'broken') has NO repair option: set requires_replacement to true. Replacement only.
- A deep scratch without deformation stays repairable (repaint), even when you classify it 'berat'.
- If you set requires_replacement to true on Quarter RH or Quarter LH, do NOT add disassembly, welding, or paint lines yourself. The system appends the mandatory quarter-replacement labour automatically (Bongkar Quarter, Las Quarter, and paint on Side Roof, Trisplang, Inner Quarter, opening bagasi).

2. VISIBLE BROKEN REPLACEMENT PARTS (Pergantian Sparepart):
In the pergantian_sparepart array, list EVERY component that is visibly broken, shattered, severed, cracked, punctured, or bent beyond repair in the photos.
Common examples to detect if visible:
- Headlamp RH / LH, Foglamp RH / LH, Cover Foglamp RH / LH, Grill Tengah, Breket Bumper RH / LH, Kaca Depan, Sealer Kaca, Radiator, Kondensor AC, Fan Shroud, Steering Rack, Shock Breaker Depan RH / LH, Lower Arm Depan RH / LH, Bullhead, Kap Mesin, Bumper Depan, Fender RH / LH.
Each item in pergantian_sparepart must have:
- name: component name in Indonesian (e.g. "Headlamp RH", "Grill Tengah", "Kaca Depan")
- condition: observed damage state in Indonesian (e.g. "Pecah", "Retak", "Patah", "Bengkok parah", "Bocor")
- quantity: integer (usually 1 or 2)
Do NOT include prices for spare parts.

Return precise counts for dents, scratches, and broken panels in EXACTLY this JSON format with NO markdown wrapping:
{
  "analysis_metadata": { "engine_processed": "model-name", "timestamp": "ISO8601" },
  "assessment": {
    "severity_classification": "ringan/sedang/berat",
    "total_panels_damaged": 0,
    "damaged_panels_detail": [
      {
        "panel_name": "exact_valid_panel_or_repair_name",
        "panel_severity": "ringan/sedang/berat",
        "damage_type": "scratch/dent/broken",
        "scratches_found": 0,
        "dents_found": 0,
        "requires_replacement": false,
        "spare_parts_needed": [
          { "name": "Nama part", "quantity": 1, "reason": "Pecah/perlu ganti" }
        ]
      }
    ],
    "pergantian_sparepart": [
      {
        "name": "Nama Sparepart",
        "condition": "Pecah/Patah/Bengkok",
        "quantity": 1
      }
    ]
  },
  "financial_estimation": {
    "currency": "IDR",
    "estimated_days_to_repair": 0,
    "spare_parts_status": "Ketersediaan dan harga sparepart masih membutuhkan konfirmasi dari vendor"
  }
}
CRITICAL: The field name MUST be "panel_name" (not "panel", not "name"). The severity field MUST be "panel_severity" (not "severity"). Only use values "ringan", "sedang", or "berat" for severity. pergantian_sparepart MUST be present as an array.`;

    // Few-shot context goes before the instructions: real finished jobs give the
    // model the workshop's actual price level and item proportions. Plain prompt
    // text, so it works with whichever model the cascade picks.
    const promptWithContext = training.text ? `${training.text}\n\n${masterPrompt}` : masterPrompt;

    let estimationResult = null;
    let usedModel = "";
    let usedEngineId = -1;
    let lastError = null;

    // Execute Fallback Cascade
    for (const configData of configs) {
      try {
        const provider = configData.provider.toLowerCase();
        
        // Per-row API key: ai_config.api_key_env names the Edge Function secret
        // to use. Empty/missing falls back to the legacy hardcoded provider key,
        // so existing rows behave exactly as before.
        const rowKey = configData.api_key_env
          ? (Deno.env.get(configData.api_key_env) ?? "")
          : "";

        if (provider.includes("google") || provider.includes("gemini")) {
          estimationResult = await callGoogleGemini(photoUrls, promptWithContext, configData.model_name, rowKey || googleApiKey);
        } else if (provider.includes("groq")) {
          estimationResult = await callOpenAICompatible(photoUrls, promptWithContext, configData.model_name, rowKey || groqApiKey, configData.api_base_url);
        } else if (provider.includes("nvidia") || provider.includes("nemotron")) {
          // NVIDIA NIM — OpenAI-compatible, accepts base64 data URLs.
          if (!rowKey) throw new Error("NVIDIA_API_KEY is not set for this row");
          estimationResult = await callOpenAICompatible(photoUrls, promptWithContext, configData.model_name, rowKey, configData.api_base_url);
        } else if (provider.includes("openai") || provider.includes("router") || provider.includes("broadandbright") || provider.includes("9router")) {
          // Covers OpenAI, OpenRouter, 9Router-style gateways, and broadandbright
          estimationResult = await callOpenAICompatible(photoUrls, promptWithContext, configData.model_name, rowKey || openaiApiKey, configData.api_base_url);
        } else {
          throw new Error(`Unsupported model provider: ${provider}`);
        }
        
        usedModel = `${configData.provider}/${configData.model_name}`;
        usedEngineId = configData.priority_order;
        break; // Success! Break the fallback loop
      } catch (err: any) {
        console.error(`Model ${configData.model_name} failed:`, err.message);
        lastError = err;
        // Loop continues to next fallback model
      }
    }

    if (!estimationResult) {
      throw new Error(`All fallback Vision AI Engines Failed. Last Error: ${lastError?.message}`);
    }

    let finalCostEstimation = null;
    try {
        let jsonStr = estimationResult;
        // Try to extract from markdown code blocks first
        const mdMatch = estimationResult.match(/```(?:json)?\s*([\s\S]+?)\s*```/) ?? estimationResult.match(/```(?:json)?\s*([\s\S]+)/);
        if (mdMatch) {
            jsonStr = mdMatch[1];
        } else {
            // Find the first { and the last }
            const firstBrace = estimationResult.indexOf('{');
            const lastBrace = estimationResult.lastIndexOf('}');
            if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
                jsonStr = estimationResult.substring(firstBrace, lastBrace + 1);
            }
        }
        
        finalCostEstimation = JSON.parse(jsonStr);
        // The model occasionally ignores the "one JSON object" instruction and
        // returns an array (or a bare string/number). Every consumer below -
        // and the clients - assume an object, so a non-object became the Dart
        // "List<dynamic> is not a subtype of Map<String, dynamic>?" crash.
        if (Array.isArray(finalCostEstimation)) {
          // A single-element array is the model wrapping its object; unwrap it.
          // Anything longer is genuinely ambiguous, so merge panels instead.
          if (finalCostEstimation.length === 1 && !Array.isArray(finalCostEstimation[0])) {
            finalCostEstimation = finalCostEstimation[0];
          } else {
            const panels = finalCostEstimation.filter(
              (p: any) => p && typeof p === 'object' && !Array.isArray(p),
            );
            finalCostEstimation = { damaged_panels_detail: panels };
          }
          console.warn('[vision-estimation] model returned an array; normalised to object');
        }
        if (!finalCostEstimation || typeof finalCostEstimation !== 'object') {
          throw new Error(`model returned ${typeof finalCostEstimation}, expected object`);
        }
        console.log('[vision-estimation] parsed keys:', Object.keys(finalCostEstimation).join(','));
        // Normalise: if model returned damaged_panels_detail at root (no assessment wrapper), wrap it
        if (!finalCostEstimation.assessment && finalCostEstimation.damaged_panels_detail) {
          const panels = finalCostEstimation.damaged_panels_detail.map((p: any) => {
            console.log('[vision-estimation] raw panel keys:', Object.keys(p).join(','), 'panel_name:', p.panel_name, 'severity:', p.severity, 'damage_type:', p.damage_type);
            return {
            panel_name: p.panel_name ?? p.panel ?? p.name ?? null,
            panel_severity: p.severity === 'severe' ? 'berat' : p.severity === 'moderate' ? 'sedang' : p.severity === 'mild' ? 'ringan' : p.panel_severity ?? 'berat',
            scratches_found: p.scratches_found ?? (p.damage_type === 'scratch' ? 1 : 0),
            dents_found: p.dents_found ?? (p.damage_type === 'dent' ? 1 : ((!p.damage_type && !p.scratches_found && !p.broken_found && !p.requires_replacement) ? 1 : 0)),
            broken_found: p.broken_found ?? (p.damage_type === 'broken' ? 1 : 0),
            requires_replacement: p.requires_replacement ?? (p.damage_type === 'broken'),
            spare_parts_needed: Array.isArray(p.spare_parts_needed) ? p.spare_parts_needed : [],
            }; // close return
          }); // close map
          finalCostEstimation = {
            analysis_metadata: finalCostEstimation.analysis_metadata ?? {},
            assessment: {
              severity_classification: finalCostEstimation.summary?.overall_severity ?? 'sedang',
              total_panels_damaged: panels.length,
              damaged_panels_detail: panels,
              pergantian_sparepart: finalCostEstimation.pergantian_sparepart ?? finalCostEstimation.assessment?.pergantian_sparepart ?? [],
            },
            financial_estimation: finalCostEstimation.financial_estimation ?? {},
          };
        }

        // The model sometimes returns NEITHER an assessment wrapper NOR a
        // damaged_panels_detail key, putting the repair items straight in
        // pergantian_sparepart. That happened on a heavily damaged car: the
        // parts list was full but there was no panel detail at all, so the
        // client parsed zero panels and the respondent app reported "No panels
        // flagged" while the customer app (which reads pergantian_sparepart
        // directly) showed a full estimate. Rebuild an assessment from the
        // parts rather than silently returning nothing.
        if (!finalCostEstimation.assessment) {
          const spareParts = Array.isArray(finalCostEstimation.pergantian_sparepart)
            ? finalCostEstimation.pergantian_sparepart
            : [];
          if (spareParts.length > 0) {
            // One panel entry per named part, so every flagged component
            // reaches the reviewer instead of being dropped.
            const panels = spareParts
              .filter((p: any) => p && typeof p === 'object' && (p.panel_name ?? p.name))
              .map((p: any) => ({
                panel_name: p.panel_name ?? p.name ?? null,
                panel_severity: p.panel_severity ?? 'berat',
                scratches_found: 0,
                dents_found: 0,
                broken_found: 1,
                requires_replacement: true,
                spare_parts_needed: [{ name: p.panel_name ?? p.name, quantity: p.quantity ?? 1, reason: p.condition ?? 'perlu ganti' }],
              }));
            finalCostEstimation = {
              analysis_metadata: finalCostEstimation.analysis_metadata ?? {},
              assessment: {
                severity_classification: 'berat',
                total_panels_damaged: panels.length,
                damaged_panels_detail: panels,
                pergantian_sparepart: spareParts,
              },
              financial_estimation: finalCostEstimation.financial_estimation ?? {},
            };
            console.warn(
              '[vision-estimation] model omitted assessment/damaged_panels_detail; rebuilt from',
              spareParts.length,
              'spare parts',
            );
          }
        }

        if (finalCostEstimation.assessment) {
          if (!finalCostEstimation.assessment.pergantian_sparepart) {
            finalCostEstimation.assessment.pergantian_sparepart = finalCostEstimation.pergantian_sparepart ?? [];
          }
        }

        // Business rules run before costing: they can force replacement-only and
        // append the quarter-replacement labour/paint lines, and the cost engine
        // must see that final panel list.
        const policy = applyEstimatorPolicies(finalCostEstimation);
        const { total: calculatedCost, pendingPricing } = calculateDeterministicCost(finalCostEstimation, liveRules);
        finalCostEstimation.financial_estimation = finalCostEstimation.financial_estimation || {};
        finalCostEstimation.financial_estimation.calculated_base_cost = calculatedCost;
        finalCostEstimation.financial_estimation.pricing_source = "live_db";
        finalCostEstimation.financial_estimation.spare_parts_status = "Ketersediaan dan harga sparepart masih membutuhkan konfirmasi dari vendor";
        finalCostEstimation.financial_estimation.repair_policy = {
          replace_only_severities: REPLACE_ONLY_SEVERITIES,
          replace_only_damage_types: REPLACE_ONLY_DAMAGE_TYPES,
          replace_only_panels: policy.replaceOnlyPanels,
        };
        if (pendingPricing.length > 0) {
          finalCostEstimation.financial_estimation.pricing_pending_items = pendingPricing;
        }
        if (policy.quarterSides.length > 0) {
          finalCostEstimation.financial_estimation.quarter_replacement = {
            applied: true,
            sides: policy.quarterSides,
            labour_items: policy.derivedItems,
            note: "Penggantian panel quarter dilas menyatu dengan Side Roof, Trisplang, opening bagasi, dan Inner Quarter — pembongkaran, pengelasan, dan pengecatan panel tersebut termasuk dalam jasa.",
          };
        }

        // Provenance for the training corpus: which past cases the model was
        // shown, plus the durable R2 keys of the photos it judged. The keys let
        // a finished job be reused as a labelled training pair later.
        finalCostEstimation.training_context = {
          cases: training.usedCaseIds.length,
          corrections: training.usedCorrections,
          case_ids: training.usedCaseIds,
        };
        finalCostEstimation.source_photos = {
          keys: extractPhotoKeys(photoUrls),
          count: photoUrls.length,
        };
        
    } catch (e: any) {
        // L-03 fix: parse fail = hard failure, not success with null structuredData
        console.error('[vision-estimation] JSON parse failed:', e.message.slice(0, 200));
        return new Response(JSON.stringify({
          success: false,
          code: 'PARSE_ERROR',
          error: 'AI response could not be parsed as valid JSON',
        }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 502,
        });
    }

    return new Response(JSON.stringify({
        success: true,
        estimation: estimationResult,
        structuredData: finalCostEstimation,
        usedModel: usedModel,
        engineId: usedEngineId,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

// --- Model API Call Wrappers ---

async function callGoogleGemini(photoUrls: string[], prompt: string, modelName: string, apiKey: string) {
  // Fetch and base64-encode ALL images, add each as a separate inline_data part
  // C-66 fix: AbortSignal.timeout for image fetch (8s per image)
  const imageParts: object[] = [];
  for (const url of photoUrls) {
    const imageResp = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!imageResp.ok) throw new Error(`Image fetch failed: HTTP ${imageResp.status}`);
    // C-66 fix: limit image size to 10MB before reading
    const contentLength = imageResp.headers.get('content-length');
    if (contentLength && parseInt(contentLength) > 10 * 1024 * 1024) {
      throw new Error('Image too large (max 10MB)');
    }
    const imageBuffer = await imageResp.arrayBuffer();
    const base64Image = base64Encode(imageBuffer);
    const mimeType = imageResp.headers.get('content-type') || 'image/jpeg';
    imageParts.push({ inline_data: { mime_type: mimeType, data: base64Image } });
  }

  // C-67 fix: send API key via header x-goog-api-key, not query string
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent`, {
    method: "POST",
    signal: AbortSignal.timeout(30000),   // C-66: 30s model timeout
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": apiKey,           // C-67: header, not query string
    },
    body: JSON.stringify({
      contents: [{
        parts: [
          { text: prompt },
          ...imageParts,     // all images injected here
        ]
      }],
      generationConfig: {
        responseMimeType: "application/json"
      }
    })
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "<unreadable body>");
    throw new Error(
      `Google API error: ${response.status} ${response.statusText} — ${errBody.slice(0, 400)}`
    );
  }
  const data = await response.json();
  if (data.candidates && data.candidates[0].content.parts[0].text) {
     return data.candidates[0].content.parts[0].text;
  }
  throw new Error("No output returned from Google AI");
}

async function callOpenAICompatible(photoUrls: string[], prompt: string, modelName: string, apiKey: string, apiBaseUrl: string) {
  const isGroq = apiBaseUrl.includes("groq");
  const isOpenRouterFree = modelName.includes("free");

  // Build content array: text prompt first, then one image_url entry per photo.
  // Images are downloaded and inlined as base64 data URLs rather than passed as
  // remote links. Gemini-backed gateways have no remote-URL image input (the
  // native API takes inline_data only), so handing them an https URL makes the
  // upstream call stall or silently drop the image. Groq/OpenAI also accept
  // data URLs, so this path is safe for every provider.
  // C-66 fix: timeout per image + size limit
  const imageParts: object[] = [];
  for (const url of photoUrls) {
    const imageResp = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!imageResp.ok) {
      throw new Error(`Image fetch failed: HTTP ${imageResp.status}`);
    }
    const contentLength = imageResp.headers.get('content-length');
    if (contentLength && parseInt(contentLength) > 10 * 1024 * 1024) {
      throw new Error('Image too large (max 10MB)');
    }
    const imageBuffer = await imageResp.arrayBuffer();
    const base64Image = base64Encode(imageBuffer);
    const mimeType = imageResp.headers.get("content-type") || "image/jpeg";
    imageParts.push({
      type: "image_url",
      image_url: { url: `data:${mimeType};base64,${base64Image}` },
    });
  }

  const contentArray: object[] = [
    { type: "text", text: prompt },
    ...imageParts,
  ];

  const payload: any = {
    model: modelName,
    messages: [{ role: "user", content: contentArray }],
    stream: true,  // Always stream — prevents 30s timeout on slow backends (e.g. broadandbright)
  };

  // Skip JSON mode for models that might not fully support strict structured format
  if (!isGroq && !isOpenRouterFree) {
    payload.response_format = { type: "json_object" };
  }

  // Reasoning models spend their completion budget on thinking before they emit
  // the answer. The NIM default cap is lower than Nemotron's reasoning length,
  // and a truncated turn comes back with content:null — the JSON parse then
  // fails and the whole engine looks broken. Give those models room.
  if (/nemotron|gpt-oss|reasoning/i.test(modelName)) {
    payload.max_tokens = 4096;
  }

  const response = await fetch(apiBaseUrl, {
    method: "POST",
    signal: AbortSignal.timeout(55000), // 55s — broadandbright needs ~23s+ for vision
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://revive.co.id",
      "X-Title": "re-V Platform"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const errBody = await response.text().catch(() => "<unreadable body>");
    throw new Error(
      `OpenAI-compatible API error: ${response.status} ${response.statusText} — ${errBody.slice(0, 400)}`
    );
  }

  // Some gateways (e.g. 9Router) always answer with SSE, even when `stream` is
  // never requested — `response.json()` throws on that body. Detect by
  // content-type and reassemble the streamed deltas when present. Groq/OpenAI
  // reply with plain JSON and keep taking the branch below.
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    const raw = await response.text();
    let assembled = "";
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) continue;
      const chunkStr = trimmed.slice(5).trim();
      if (!chunkStr || chunkStr === "[DONE]") continue;
      try {
        const chunk = JSON.parse(chunkStr);
        const choice = (chunk.choices ?? [])[0] ?? {};
        // Skip reasoning_content-only chunks (thinking models emit these before the real answer)
        const piece = choice.delta?.content ?? choice.message?.content ?? null;
        if (piece != null && piece !== "") assembled += piece;
        else if (choice.delta?.reasoning_content) { /* skip thinking tokens */ }
      } catch {
        // Skip keep-alive / non-JSON frames
      }
    }
    if (!assembled.trim()) {
      console.error("[vision-estimation] SSE assembled empty. Raw snippet:", raw.slice(0, 500));
      throw new Error("OpenAI-compatible API returned an SSE stream with no content");
    }
    console.log("[vision-estimation] SSE assembled length:", assembled.length, "snippet:", assembled.slice(0, 200));
    return assembled;
  }

  const data = await response.json();
  return data.choices[0].message.content;
}
