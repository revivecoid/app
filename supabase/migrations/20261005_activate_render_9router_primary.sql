-- =============================================================================
-- Activate Render-hosted 9router as primary estimation engine
-- Date: 2026-10-05
--
-- Why:
--   9router previously ran on Cloud Shell (ephemeral URL, cold-start timeouts).
--   It is now deployed on Render (ninerouter-8lml.onrender.com) with a GitHub
--   Actions keep-alive pinging /v1/models every 10 minutes.
--
--   Model: ag/gemini-3-flash (fast, reliable on Render)
--   Key:   NINEROUTER_API_KEY edge-function secret (already set)
--
-- Strategy:
--   - Update the existing 9Router row to use ag/gemini-3-flash, set priority 1
--   - Demote native gemini-3.5-flash to priority 2 (keep as fallback)
--   - Keep Groq at priority 3, openrouter disabled
-- =============================================================================

-- 1. Update 9Router row: new model, priority 1, re-activate
UPDATE public.ai_config
   SET model_name     = 'ag/gemini-3-flash',
       is_active      = true,
       priority_order = 1,
       api_base_url   = 'https://ninerouter-8lml.onrender.com/v1/chat/completions',
       api_key_env    = 'NINEROUTER_API_KEY'
 WHERE provider = '9Router';

-- 2. Demote native Gemini to priority 2
UPDATE public.ai_config
   SET priority_order = 2
 WHERE provider = 'google'
   AND model_name ILIKE '%gemini%flash%';

-- 3. Groq stays at priority 3 (no change needed, but make explicit)
UPDATE public.ai_config
   SET priority_order = 3
 WHERE provider = 'groq';

-- Verify
SELECT model_name, provider, is_active, priority_order,
       COALESCE(api_key_env, '-') AS key_env, api_base_url
  FROM public.ai_config
 ORDER BY priority_order;
