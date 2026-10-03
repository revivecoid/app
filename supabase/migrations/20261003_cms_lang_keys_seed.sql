-- =============================================================================
-- 20261003_cms_lang_keys_seed.sql
-- Seed all AppL l10n language keys into cms_settings.
-- category='lang', keys follow basekey_en / basekey_id convention.
-- Safe to re-run: ON CONFLICT DO NOTHING.
-- =============================================================================

-- Guard: ensure cms_settings has the category column (idempotent).
ALTER TABLE public.cms_settings
  ADD COLUMN IF NOT EXISTS category TEXT;

-- Seed language keys.
INSERT INTO public.cms_settings (key, value, category) VALUES

  -- app_name
  ('app_name_en', 'Revive', 'lang'),
  ('app_name_id', 'Revive', 'lang'),

  -- app_tagline
  ('app_tagline_en', 'Automotive Body Repair Portal', 'lang'),
  ('app_tagline_id', 'Portal Perbaikan Bodi Otomotif', 'lang'),

  -- hero_tag_badge
  ('hero_tag_badge_en', 'AUTOMOTIVE AI CARE', 'lang'),
  ('hero_tag_badge_id', 'PERAWATAN OTOMOTIF AI', 'lang'),

  -- hero_title
  ('hero_title_en', 'Body Repair Made Simple.', 'lang'),
  ('hero_title_id', 'Perbaikan Bodi, Lebih Mudah.', 'lang'),

  -- hero_subtitle
  ('hero_subtitle_en', 'Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.', 'lang'),
  ('hero_subtitle_id', 'Estimasi perbaikan instan & pelacakan real-time. Kembalikan kilap mobilmu lebih cepat, dengan transparansi penuh.', 'lang'),

  -- hero_cta_button
  ('hero_cta_button_en', 'Get Free AI Estimate', 'lang'),
  ('hero_cta_button_id', 'Dapatkan Estimasi AI Gratis', 'lang'),

  -- network_title
  ('network_title_en', 'Jabodetabek Certified Network', 'lang'),
  ('network_title_id', 'Jaringan Tersertifikasi Jabodetabek', 'lang'),

  -- network_desc
  ('network_desc_en', 'Over 38 OEM-compliant spray booths with digitized color-matching precision down to 99.4% factory accuracy.', 'lang'),
  ('network_desc_id', 'Lebih dari 38 spray booth berstandar OEM dengan presisi pencocokan warna digital hingga 99,4% akurasi pabrik.', 'lang'),

  -- about_title
  ('about_title_en', 'About Revive', 'lang'),
  ('about_title_id', 'Tentang Revive', 'lang'),

  -- about_tagline
  ('about_tagline_en', 'Democratizing access to premium body repair.', 'lang'),
  ('about_tagline_id', 'Membuka akses ke perbaikan bodi premium.', 'lang'),

  -- about_story
  ('about_story_en', 'Revive was founded in 2024 with one mission: make premium body repair accessible to every Indonesian driver.', 'lang'),
  ('about_story_id', 'Revive didirikan tahun 2024 dengan satu misi: membuka akses perbaikan bodi premium untuk setiap pengemudi Indonesia.', 'lang'),

  -- about_mission
  ('about_mission_en', 'Our mission is to digitize the body repair supply chain...', 'lang'),
  ('about_mission_id', 'Misi kami adalah mendigitalisasi rantai pasokan perbaikan bodi...', 'lang'),

  -- about_vision
  ('about_vision_en', 'To be the most trusted automotive repair platform in Southeast Asia.', 'lang'),
  ('about_vision_id', 'Menjadi platform perbaikan otomotif paling terpercaya di Asia Tenggara.', 'lang'),

  -- value_1_title
  ('value_1_title_en', 'Transparent', 'lang'),
  ('value_1_title_id', 'Transparan', 'lang'),

  -- value_1_sub
  ('value_1_sub_en', 'Real cost estimates, no hidden fees', 'lang'),
  ('value_1_sub_id', 'Estimasi biaya real, tidak ada biaya tersembunyi', 'lang'),

  -- value_2_title
  ('value_2_title_en', 'Fast', 'lang'),
  ('value_2_title_id', 'Cepat', 'lang'),

  -- value_2_sub
  ('value_2_sub_en', 'Digital process from claim to vehicle pickup', 'lang'),
  ('value_2_sub_id', 'Proses digital dari klaim hingga pengambilan kendaraan', 'lang'),

  -- value_3_title
  ('value_3_title_en', 'Trusted', 'lang'),
  ('value_3_title_id', 'Terpercaya', 'lang'),

  -- value_3_sub
  ('value_3_sub_en', '90-day work guarantee at all our partners', 'lang'),
  ('value_3_sub_id', '90 hari garansi pengerjaan di semua mitra kami', 'lang'),

  -- value_4_title
  ('value_4_title_en', 'Innovative', 'lang'),
  ('value_4_title_id', 'Inovatif', 'lang'),

  -- value_4_sub
  ('value_4_sub_en', 'Industry-leading AI damage detection & pricing', 'lang'),
  ('value_4_sub_id', 'AI damage detection & pricing terdepan di industri', 'lang'),

  -- partner_cta_title
  ('partner_cta_title_en', 'Grow Your Workshop Revenue', 'lang'),
  ('partner_cta_title_id', 'Kembangkan Pendapatan Bengkel Anda', 'lang'),

  -- partner_cta_sub
  ('partner_cta_sub_en', 'Join Indonesia''s fastest-growing automotive repair network.', 'lang'),
  ('partner_cta_sub_id', 'Bergabunglah dengan jaringan perbaikan otomotif yang paling cepat berkembang di Indonesia.', 'lang'),

  -- cta_register
  ('cta_register_en', 'Register', 'lang'),
  ('cta_register_id', 'Daftar', 'lang'),

  -- stat_partners
  ('stat_partners_en', '38+', 'lang'),
  ('stat_partners_id', '38+', 'lang'),

  -- stat_rating
  ('stat_rating_en', '4.9/5', 'lang'),
  ('stat_rating_id', '4.9/5', 'lang'),

  -- stat_jobs
  ('stat_jobs_en', '12,000+', 'lang'),
  ('stat_jobs_id', '12.000+', 'lang'),

  -- footer_copyright
  ('footer_copyright_en', '© 2025 Revive Technologies Indonesia', 'lang'),
  ('footer_copyright_id', '© 2025 Revive Technologies Indonesia', 'lang'),

  -- footer_tagline
  ('footer_tagline_en', 'AI-Powered Automotive Body Repair', 'lang'),
  ('footer_tagline_id', 'Perbaikan Bodi Otomotif Bertenaga AI', 'lang')

ON CONFLICT (key) DO NOTHING;
