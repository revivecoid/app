-- =============================================================================
-- Add 9Router gateway as an optional fallback vision model
-- Date: 2026-09-19
--
-- Why:
--   The estimation engine cascades through ai_config rows ordered by
--   priority_order. This registers an OpenAI-compatible gateway row with its
--   OWN api key (via api_key_env) so it does not consume the shared
--   OPENAI_API_KEY secret.
--
-- Requires the matching edge-function change in supabase/functions/
-- vision-estimation/index.ts:
--   1. callOpenAICompatible reassembles SSE responses. This gateway ALWAYS
--      answers with text/event-stream even when `stream` is never requested,
--      and `response.json()` throws on such a body.
--   2. api_key_env is resolved per row, falling back to the legacy provider key.
--
-- Measured 2026-09-19 (vision + response_format=json_object, correct result):
--   ag/gemini-pro-agent ..... ~21s   via SSE  <- deployed path (no `stream` key)
--   ag/gemini-3.1-pro-low ... ~13s   via SSE
--   ag/gemini-pro-agent ..... ~146s  with `stream: false`  <- do NOT use
--   ag/gemini-3.1-pro-low ... >300s  with `stream: false`  <- hung
--   Native gemini-3.5-flash completes in seconds, so this row is registered as
--   a LAST-RESORT fallback (priority_order 4), not as a primary engine.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Per-row API key support.
--    NULL keeps the existing hardcoded-key behaviour for all current rows.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ai_config
  ADD COLUMN IF NOT EXISTS api_key_env TEXT;

COMMENT ON COLUMN public.ai_config.api_key_env IS
  'Name of the Edge Function secret holding this row''s API key. NULL = use the legacy provider key.';


-- ---------------------------------------------------------------------------
-- 2. Register the gateway row (last-resort fallback).
-- ---------------------------------------------------------------------------
INSERT INTO public.ai_config (
  model_name, provider, is_active, priority_order,
  api_base_url, payload_format, api_key_env
)
VALUES (
  'ag/gemini-pro-agent',
  '9Router',
  true,
  4,
  'https://ninerouter-8lml.onrender.com/v1/chat/completions',
  'openai',
  'NINEROUTER_API_KEY'
)
ON CONFLICT (model_name) DO UPDATE SET
  provider       = EXCLUDED.provider,
  is_active      = EXCLUDED.is_active,
  priority_order = EXCLUDED.priority_order,
  api_base_url   = EXCLUDED.api_base_url,
  payload_format = EXCLUDED.payload_format,
  api_key_env    = EXCLUDED.api_key_env;


-- ---------------------------------------------------------------------------
-- 3. Verify — expect 4 rows, all is_active=true, our row last.
-- ---------------------------------------------------------------------------
SELECT model_name, provider, is_active, priority_order,
       payload_format, api_key_env, api_base_url
FROM public.ai_config
ORDER BY priority_order;
