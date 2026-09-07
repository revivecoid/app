import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const googleApiKey = Deno.env.get("GOOGLE_AI_API_KEY") ?? "";
const groqApiKey = Deno.env.get("GROQ_API_KEY") ?? "";
const openaiApiKey = Deno.env.get("OPENAI_API_KEY") ?? "";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
};

// ── LivePricingRule: shape of a row from the pricing_rules table ──
interface LivePricingRule {
  label: string;
  base_price: number;
  sedang_multiplier: number;
  berat_multiplier: number;
}

// ── Fetches live pricing rules from DB; gracefully falls back to hardcoded map ──
async function loadPricingRules(): Promise<LivePricingRule[]> {
  try {
    const { data, error } = await supabase
      .from("pricing_rules")
      .select("label, base_price, sedang_multiplier, berat_multiplier");

    if (error || !data || data.length === 0) {
      console.warn("pricing_rules fetch failed or empty — using hardcoded fallback.", error?.message);
      return Object.entries(FALLBACK_PRICES).map(([label, base_price]) => ({
        label,
        base_price,
        sedang_multiplier: 1.5,
        berat_multiplier: 2.0,
      }));
    }
    return data as LivePricingRule[];
  } catch (err) {
    console.error("Unexpected error loading pricing_rules:", err);
    return Object.entries(FALLBACK_PRICES).map(([label, base_price]) => ({
      label,
      base_price,
      sedang_multiplier: 1.5,
      berat_multiplier: 2.0,
    }));
  }
}

// ── Deterministic cost engine — uses live DB rules, not hardcoded map ──
function calculateDeterministicCost(
  structuredData: any,
  rules: LivePricingRule[]
): number {
  if (!structuredData?.assessment?.damaged_panels_detail) return 0;

  // Build a fast lookup map: label → rule
  const ruleMap = new Map<string, LivePricingRule>(
    rules.map((r) => [r.label, r])
  );

  let totalCost = 0;
  for (const panel of structuredData.assessment.damaged_panels_detail) {
    const name: string = panel.panel_name;
    const severity: string = (panel.panel_severity || "ringan").toLowerCase();

    const rule = ruleMap.get(name);
    const basePrice = rule?.base_price ?? FALLBACK_PRICES[name] ?? 500000;

    let multiplier = 1.0;
    if (severity === "sedang") {
      multiplier = rule?.sedang_multiplier ?? 1.5;
    } else if (severity === "berat") {
      multiplier = rule?.berat_multiplier ?? 2.0;
    }

    const panelCost = basePrice * multiplier;
    panel.calculated_cost = panelCost; // inject per-panel cost for frontend display
    panel.applied_multiplier = multiplier;
    totalCost += panelCost;
  }
  return totalCost;
}



serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
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

    // Load AI config + live pricing rules in parallel for minimum latency
    const [{ data: configs, error: configError }, liveRules] = await Promise.all([
      supabase
        .from("ai_config")
        .select("*")
        .eq("is_active", true)
        .order("priority_order", { ascending: true }),
      loadPricingRules(),
    ]);

    if (configError || !configs || configs.length === 0) {
      throw new Error("Failed to load active AI configuration (No active models found)");
    }

    const panelsConstraint = (selectedPanels && selectedPanels.length > 0)
        ? `\nIMPORTANT: The user has reported possible damage on these panels: [${selectedPanels.join(', ')}]. Use this as a HINT of which areas to inspect closely. However, you must ONLY include a panel in your response if you can VISUALLY CONFIRM actual damage (scratches, dents, deformation, or paint damage) on it from the image. If a listed panel shows NO visible damage in the image, you MUST OMIT it from damaged_panels_detail entirely. Do NOT assign default or assumed severity to panels that are not clearly damaged in the image. Accuracy is critical — do not include unverifiable panels.`
        : "";

    const masterPrompt = `Analyze the car body damage from these images.
Valid panel names are: Bumper Depan, Spoiler Bumper depan, Kap Mesin, Bumper Belakang, Spoiler Bumper Belakang, Bagasi, Spoiler Bagasi, Fender RH, Pintu Depan RH, Spion RH, Pintu Belakang RH, Quarter RH, Trisplang RH, Side Roof RH, Fender LH, Pintu Depan LH, Spion LH, Pintu Belakang LH, Quarter LH, Trisplang LH, Side Roof LH, Roof, Cover.${panelsConstraint}

For each damaged panel found, classify its specific severity into: 'ringan', 'sedang', or 'berat'.
Also classify the overall severity of the car damage.
Return precise counts for dents, scratches, and broken panels in the exact following JSON format:
{
  "analysis_metadata": { "engine_processed": "model-name", "timestamp": "ISO8601" },
  "assessment": {
    "severity_classification": "ringan/sedang/berat",
    "total_panels_damaged": 0,
    "damaged_panels_detail": [
      { "panel_name": "exact_valid_panel_name", "panel_severity": "ringan/sedang/berat", "scratches_found": 0, "dents_found": 0, "requires_replacement": false }
    ]
  },
  "financial_estimation": { "currency": "IDR", "estimated_days_to_repair": 0 }
}`;

    let estimationResult = null;
    let usedModel = "";
    let lastError = null;

    // Execute Fallback Cascade
    for (const configData of configs) {
      try {
        const provider = configData.provider.toLowerCase();
        
        if (provider.includes("google") || provider.includes("gemini")) {
          estimationResult = await callGoogleGemini(photoUrls, masterPrompt, configData.model_name, googleApiKey);
        } else if (provider.includes("groq")) {
          estimationResult = await callOpenAICompatible(photoUrls, masterPrompt, configData.model_name, groqApiKey, configData.api_base_url);
        } else if (provider.includes("openai")) {
          estimationResult = await callOpenAICompatible(photoUrls, masterPrompt, configData.model_name, openaiApiKey, configData.api_base_url);
        } else {
          throw new Error(`Unsupported model provider: ${provider}`);
        }
        
        usedModel = `${configData.provider}/${configData.model_name}`;
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
        const mdMatch = estimationResult.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
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
        const calculatedCost = calculateDeterministicCost(finalCostEstimation, liveRules);
        finalCostEstimation.financial_estimation = finalCostEstimation.financial_estimation || {};
        finalCostEstimation.financial_estimation.calculated_base_cost = calculatedCost;
        finalCostEstimation.financial_estimation.pricing_source = "live_db";
        
    } catch (e: any) {
        estimationResult = estimationResult + "\n\n[PARSE ERROR]: " + e.message;
    }

    return new Response(JSON.stringify({
        success: true,
        estimation: estimationResult,
        structuredData: finalCostEstimation,
        usedModel: usedModel
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
  const imageParts: object[] = [];
  for (const url of photoUrls) {
    const imageResp = await fetch(url);
    if (!imageResp.ok) throw new Error(`Failed to fetch image from URL: ${url}`);
    const imageBuffer = await imageResp.arrayBuffer();
    let binary = '';
    const bytes = new Uint8Array(imageBuffer);
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64Image = btoa(binary);
    const mimeType = imageResp.headers.get('content-type') || 'image/jpeg';
    imageParts.push({ inline_data: { mime_type: mimeType, data: base64Image } });
  }

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
    throw new Error(`Google API error: ${response.status} ${response.statusText}`);
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

  // Build content array: text prompt first, then one image_url entry per photo
  const contentArray: object[] = [
    { type: "text", text: prompt },
    ...photoUrls.map((url) => ({ type: "image_url", image_url: { url } })),
  ];

  const payload: any = {
    model: modelName,
    messages: [{ role: "user", content: contentArray }],
  };

  // Skip JSON mode for models that might not fully support strict structured format
  if (!isGroq && !isOpenRouterFree) {
    payload.response_format = { type: "json_object" };
  }

  const response = await fetch(apiBaseUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://revive.co.id",
      "X-Title": "re-V Platform"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`OpenAI-compatible API error: ${response.status} ${response.statusText}`);
  }
  const data = await response.json();
  return data.choices[0].message.content;
}
