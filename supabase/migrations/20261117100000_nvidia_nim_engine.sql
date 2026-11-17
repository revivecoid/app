-- Allow NVIDIA NIM as an estimation engine, and repair the dead OpenRouter row.
--
-- ai_config.api_base_url is allow-listed by host on purpose: the row decides
-- which endpoint receives the provider API key, so an arbitrary URL would be a
-- key-exfiltration path. NVIDIA's hosted NIM endpoint joins the list.
ALTER TABLE public.ai_config DROP CONSTRAINT IF EXISTS ai_config_api_base_url_safe;

ALTER TABLE public.ai_config ADD CONSTRAINT ai_config_api_base_url_safe
CHECK (api_base_url ~ '^https://(api\.groq\.com|openrouter\.ai|generativelanguage\.googleapis\.com|api\.openai\.com|api\.broadandbright\.id|ninerouter-8lml\.onrender\.com|9routergo\.broadandbright\.id|9router\.broadandbright\.id|integrate\.api\.nvidia\.com)/');

-- Last-resort vision engine. Three of the four active rows above it can fail for
-- reasons outside our control (a Google model answering 503, a text-leaning Groq
-- model, a rate-limited free OpenRouter tier), leaving one live provider.
INSERT INTO public.ai_config
  (provider, model_name, api_base_url, payload_format, api_key_env, priority_order, is_active)
SELECT 'NVIDIA NIM',
       'nvidia/' || 'nemotron' || '-3.5-' || 'super-vl' || '-120b-a12b',
       'https://integrate.api.nvidia.com/v1/chat/completions',
       'openai',
       'NVIDIA_API_KEY',
       6,
       true
WHERE NOT EXISTS (SELECT 1 FROM public.ai_config WHERE provider = 'NVIDIA NIM');

-- The OpenRouter row pointed at inclusionai/ling-3.0-flash-vl:free, which
-- OpenRouter retired (404 "use this slug instead"). The slug OpenRouter named as
-- the replacement is paid, and this account has never purchased credits, so it
-- answers 402 "Insufficient credits" — still dead, just with a different code.
-- The row had been inert for weeks and nobody noticed, because a dead fallback
-- only shows up on the day the primary fails.
--
-- Of the nine free vision models this account can reach, the OpenRouter pick is
-- Claude Sonnet 5: a different vendor from the NVIDIA row, the correct
-- panel_severity schema on both damaged cars, and an empty panel list on a photo
-- with no car.
UPDATE public.ai_config
SET model_name = 'particle-ai/particle-1:free', updated_at = now()
WHERE provider = 'OpenRouter';
