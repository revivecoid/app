-- =============================================================================
-- Fix the Groq fallback model id
-- Date: 2026-09-19
--
-- `qwen/qwen3.6-27b` was set directly on the live row (never in a migration) and
-- does not resolve for this project's Groq key. Confirmed end-to-end through the
-- deployed edge function, with the Groq row isolated so its own error surfaced:
--
--   qwen/qwen3.6-27b                             404 model_not_found
--   meta-llama/llama-4-scout-17b-16e-instruct    404 model_not_found
--   meta-llama/llama-4-maverick-17b-128e-instruct 404 model_not_found
--   qwen/qwen3.8-27b                             OK, 2.3s / 2.0s  <- this one
--
-- Both llama-4 ids and the previously registered llama-3.2-*vision* ids are
-- unavailable to this key; Groq's current vision lineup is the qwen3.x pair.
-- Always probe a candidate id through the function before trusting it.
--
-- NOTE: the Groq row is free-tier and returns 429 under burst (1 of 3 isolated
-- runs). That is acceptable for a fallback — the cascade moves on — but the row
-- should not be promoted above the native Gemini primary.
-- =============================================================================

UPDATE public.ai_config
   SET model_name = 'qwen/qwen3.8-27b'
 WHERE provider = 'Groq';


-- ---------------------------------------------------------------------------
-- Verify — expect the four rows below, only 9Router inactive.
-- ---------------------------------------------------------------------------
SELECT priority_order, model_name, provider, is_active,
       COALESCE(api_key_env, '-') AS key_env
  FROM public.ai_config
 ORDER BY priority_order;
