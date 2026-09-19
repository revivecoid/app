-- =============================================================================
-- Activate OpenRouter as the tertiary fallback vision engine
-- Date: 2026-09-19
--
-- Replaces the placeholder row that was seeded as a bare `openrouter/free`
-- model id with no API key. Two reasons it could not work before:
--   1. No OPENROUTER_API_KEY existed in Edge Function secrets, and the row's
--      api_key_env was NULL, so the cascade fell back to OPENAI_API_KEY and
--      sent an OpenAI key to openrouter.ai (401).
--   2. `openrouter/free` is a REAL OpenRouter model id, but it is an
--      auto-router: it picks a different backing model per call. Measured,
--      1 of 2 identical requests was routed to
--      nvidia/nemotron-3.5-content-safety:free, which replied "User Safety:
--      safe" instead of a damage report. Unusable for estimation.
--
-- Pinned to a specific vision-language model instead. Verified with the
-- engine's actual master prompt and image payload (96x96 test image):
--   inclusionai/ling-3.0-flash-vl:free ... 4.8s / 4.5s / 2.9s, schema-OK x3
--   nex-agi/nex-n2.5-pro:free ........... 21.2s / 5.5s / 7.9s, schema-OK x3
--   dots-studio/dots-3-note-preview:free  18.8s, schema-OK
--   nvidia/nemotron-3-nano-omni-...:free  30.4s, schema-OK
--   thinkingmachines/inkling:free ........ HTTP 403 (agentic harnesses only)
-- ling-3.0-flash-vl chosen: fastest and most consistent, dedicated VL model.
--
-- Requires OPENROUTER_API_KEY to exist as an Edge Function secret.
-- This relies on the edge-function changes already deployed:
--   - per-row ai_config.api_key_env resolution
--   - provider.includes("router") routing (provider label is 'OpenRouter')
--   - images inlined as base64 data URLs
--
-- KNOWN LIMIT: free-tier models are subject to upstream rate limits
-- (HTTP 429 seen on other :free models during testing). Acceptable for a
-- tertiary fallback; not suitable as a primary engine.
-- =============================================================================

UPDATE public.ai_config
   SET model_name   = 'inclusionai/ling-3.0-flash-vl:free',
       provider     = 'OpenRouter',
       api_base_url = 'https://openrouter.ai/api/v1/chat/completions',
       payload_format = 'openai',
       api_key_env  = 'OPENROUTER_API_KEY',
       is_active    = true,
       priority_order = 3
 WHERE model_name = 'openrouter/free'
    OR priority_order = 3;


-- ---------------------------------------------------------------------------
-- Verify — expect Gemini(1) + Groq(2) + OpenRouter(3) active, 9Router inactive.
-- ---------------------------------------------------------------------------
SELECT model_name, provider, is_active, priority_order,
       COALESCE(api_key_env, '-') AS key_env, api_base_url
  FROM public.ai_config
 ORDER BY priority_order;
