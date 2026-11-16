-- Correct the claims the customer-facing pages make.
--
-- The pilot has one partner workshop, no ratings, no insurer integration and no
-- warranty programme, yet the CMS copy promised 38+ partner hubs, 4.9/5
-- ratings, 12K+ drivers, 98.7% on-time delivery "verified by telemetry", a
-- 24-month paint guarantee, a 90-day work guarantee at every partner, and
-- automatic Garda Oto / Astra claim submission. Every one of those is a
-- promise re-V cannot keep, and a customer who relies on them is worse off
-- than one who was told the truth.
--
-- The copy now describes the flow re-V actually runs: an AI estimate first,
-- a final price from the workshop after the physical inspection, approved on
-- the invoice before the work starts, and progress photos of the work.

INSERT INTO public.cms_settings (key, value, category, updated_at) VALUES
  ('about_mission',
   'To make vehicle body repair in Indonesia transparent and easy to follow: an estimate first, a clear price after the inspection, and photos of the work.',
   'about', now()),
  ('about_mission_id',
   'Menjadikan perbaikan bodi kendaraan di Indonesia transparan dan mudah diikuti: estimasi lebih dulu, harga jelas setelah inspeksi, dan foto pengerjaan.',
   'about', now()),
  ('about_tagline',
   'Building a repair process you can follow: an estimate, an agreed price, and photos of the work.',
   'about', now()),
  ('about_tagline_id',
   'Membangun proses perbaikan yang bisa diikuti: estimasi, harga yang disepakati, dan foto pengerjaan.',
   'about', now()),
  ('value_3_sub',
   'The price and the terms come from the workshop, and they are agreed before the work starts',
   'about', now()),
  ('value_3_sub_id',
   'Harga dan ketentuan berasal dari bengkel, dan disepakati sebelum pengerjaan dimulai',
   'about', now()),
  ('value_4_sub',
   'AI damage estimation, with the final price set after the inspection',
   'about', now()),
  ('value_4_sub_id',
   'Estimasi kerusakan dengan AI, harga final ditentukan setelah inspeksi',
   'about', now()),
  ('faq_2_a',
   'Garansi dari re-V belum ada. Harga final dan ketentuan pengerjaan berasal dari bengkel mitra pada invoice, dan jaminan apa pun mengikuti invoice bengkel tersebut. Yang dikendalikan re-V adalah alurnya: estimasi AI lebih dulu, harga final setelah inspeksi fisik, dan foto progres pengerjaan.',
   'faq', now()),
  ('faq_3_a',
   'Buka bagian "Digital Garage" di profil Anda. Live Tracker menampilkan tahap yang sedang berjalan - dari intake, pengerjaan bodi dan pengecatan, hingga serah terima. Setiap tahap didokumentasi dengan foto.',
   'faq', now()),
  ('faq_4_a',
   'Belum diproses otomatis. Belum ada integrasi dengan Garda Oto atau Astra, dan tidak ada dokumen klaim yang dikirim atas nama Anda - hubungi bengkel atau perusahaan asuransi Anda secara langsung.',
   'faq', now()),
  ('faq_5_a',
   'Pilot kami berjalan di Jakarta Selatan bersama satu bengkel mitra re-V. Area lain dibuka menyusul ketika bengkel mitra tersedia di sana.',
   'faq', now()),
  ('faq_6_q',
   'Apakah ada Garansi Cat re-V?',
   'faq', now()),
  ('faq_6_a',
   'Belum ada. Saat ini re-V tidak menerbitkan sertifikat garansi dan tidak menerbitkannya setelah serah terima. Jika bengkel mitra memberi jaminan atas pekerjaannya, jaminan itu tertulis di invoice bengkel.',
   'faq', now()),
  ('badge_1_value', '1', 'landing', now()),
  ('badge_1_label', 'Active Partner Workshop', 'landing', now()),
  ('badge_1_label_id', 'Bengkel Mitra Aktif', 'landing', now()),
  ('badge_2_value', 'Inspection', 'landing', now()),
  ('badge_2_label', 'Final Price', 'landing', now()),
  ('badge_2_label_id', 'Harga Final', 'landing', now()),
  ('badge_3_value', 're-V', 'landing', now()),
  ('badge_3_label', 'AI Estimate', 'landing', now()),
  ('badge_3_label_id', 'Estimasi AI', 'landing', now())
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      category = EXCLUDED.category,
      updated_at = now();
