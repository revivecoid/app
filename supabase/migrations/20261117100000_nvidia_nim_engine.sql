-- Allow NVIDIA NIM as an estimation engine.
--
-- ai_config.api_base_url is allow-listed by host on purpose: the row decides
-- which endpoint receives the provider API key, so an arbitrary URL would be a
-- key-exfiltration path. NVIDIA's hosted NIM endpoint joins the list.
ALTER TABLE public.ai_config DROP CONSTRAINT IF EXISTS ai_config_api_base_url_safe;

ALTER TABLE public.ai_config ADD CONSTRAINT ai_config_api_base_url_safe
CHECK (api_base_url ~ '^https://(api\.groq\.com|openrouter\.ai|generativelanguage\.googleapis\.com|api\.openai\.com|api\.broadandbright\.id|ninerouter-8lml\.onrender\.com|9routergo\.broadandbright\.id|9router\.broadandbright\.id|integrate\.api\.nvidia\.com)/');

-- Last-resort vision engine. Three of the four active rows above it can fail for
-- reasons outside our control (invalid Google key, a text-only Groq model, a
-- rate-limited free OpenRouter model), leaving one live provider.
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

-- The OpenRouter fallback pointed at inclusionai/ling-3.0-flash-vl:free, which
-- OpenRouter retired: the API answers 404 "This model is unavailable for free —
-- use this slug instead". The row had therefore been dead since the model went
-- paid, so the cascade dropped from four engines to three without anyone
-- noticing. Point it at the slug OpenRouter itself names.
UPDATE public.ai_config
SET model_name = 'inclusionai/ling-3.0-flash-vl', updated_at = now()
WHERE provider = 'OpenRouter' AND model_name LIKE '%:free';
