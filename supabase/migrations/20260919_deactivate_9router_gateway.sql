-- =============================================================================
-- Deactivate the 9Router gateway in the estimation engine
-- Date: 2026-09-19
--
-- Supersedes 20260919_add_9router_gateway_model.sql (which registered the row).
--
-- Why it is off:
--   The endpoint is not reliable enough to serve estimations. Measured across
--   one session, with identical payloads and a correct-answer control:
--     ag/gemini-3-flash ......... 19.3s ok, 59.4s ok, then 60s x3 timeout
--     ag/gemini-pro-agent ....... 21.0s ok, then 100s / 180s / 240s / 240s timeout
--     ag/gemini-3.1-pro-low ..... 12.7s ok, then >300s timeout
--     ag/claude-sonnet-4-6 ...... timeout at 120s
--     ag/gemini-3.5-flash-extra-low  replied "no longer available"
--   /models kept answering in ~1s while completions hung, i.e. the router is
--   healthy but the upstream model calls are not. Progressive degradation over
--   the session points at upstream congestion / rate limiting.
--
-- The row is deactivated, NOT deleted: the model_name, api_base_url and
-- api_key_env are retained so the gateway can be re-tried by flipping
-- is_active back to true once it behaves.
--
-- Note the edge-function changes made while testing this gateway are
-- provider-agnostic and stay in place (supabase/functions/vision-estimation):
--   - per-row ai_config.api_key_env resolution
--   - SSE reassembly for gateways that never return plain JSON
--   - provider response bodies surfaced in thrown errors
--   - images inlined as base64 data URLs (see below)
-- =============================================================================

UPDATE public.ai_config
   SET is_active = false
 WHERE provider = '9Router'
    OR model_name = 'ag/gemini-pro-agent';


-- ---------------------------------------------------------------------------
-- Verify — expect: Gemini + Groq active, 9Router and openrouter/free inactive.
-- ---------------------------------------------------------------------------
SELECT model_name, provider, is_active, priority_order,
       COALESCE(api_key_env, '-') AS key_env
  FROM public.ai_config
 ORDER BY priority_order;
