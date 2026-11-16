# Perbaikan temuan review CTO — 16 November 2026

Dokumen ini memetakan 18 temuan dari *Review Sistem & Business Process Flow re-V*
(Mas Yoga) ke perbaikannya. Semua baris di bawah sudah ada di `main` dan sudah
diterapkan ke database produksi.

Referensi temuan: `ReviewSytemBusinessProcessFLOWREV.pdf` (30 halaman, uji
dilakukan di `main` commit `7bb371a` dengan database lokal yang dibangun dari 95
migrasi repo).

---

## P0 — memutus alur uang atau menyesatkan pengguna

| # | Temuan | Perbaikan | Lokasi |
|---|---|---|---|
| 1 | Booking menampilkan "berhasil" padahal order tidak masuk bengkel | `execute_auto_assign` sekarang melempar error bila auto-assign mati atau tidak ada bengkel yang cocok; sakelar `auto_assign_settings.is_active` diaktifkan. Tombol booking menampilkan keadaan sebenarnya (tercatat, menunggu penugasan), bukan "dikonfirmasi". | `20261116160000_core_flow_repairs.sql`, `booking_scheduling_screen.dart` |
| 2 | Halaman bayar menampilkan Rp 0 | `admin_release_invoice` menyalin `final_cost` ke `repair_jobs`; `create_payment` membaca kolom yang sama. Jalur transfer manual kini membuat baris `payments` dan mengunggah slip ke `jobs/<job_id>/payment_proof/…`. | `20261116160000_core_flow_repairs.sql`, `checkout_payment_controller.dart`, `r2-presign/index.ts` |
| 3 | Halaman persetujuan invoice tidak tertaut dari tombol mana pun | Tombol di landing dan timeline kini membuka `/invoice/<jobId>` (halaman invoice), bukan `/checkout?paymentOnly=true` yang tidak ada. | `customer_landing_screen.dart`, `live_stepper_timeline.dart` |
| 4 | Verifikasi slip admin menampilkan data contoh | Modal verifikasi dibongkar: tidak ada lagi slip BCA yang digambar, SHA256 palsu, atau "EXACT MATCH 99,4%". Modal membaca baris `payments` yang sebenarnya, membuka `proof_file_key` asli dari R2, dan "Setujui" memanggil `admin_review_payment` / `admin_record_manual_payment` sehingga invoice ditandai lunas. | `desktop_parts/verification_modal.dart`, `master_admin_desktop.dart` |
| 5 | Estimasi tidak bisa diubah menjadi order | `create_job_from_estimation` menulis `service_area` yang bukan nilai enum (dan kolom `repair_photos` yang tidak pernah ada). Sekarang di-normalkan ke enum yang valid dan foto disimpan dengan `r2_file_key` + `step_context`. | `20261116160000_core_flow_repairs.sql` |
| 6 | Pelanggan tidak bisa membuka foto progres | `repair_photos` punya policy INSERT saja; sekarang ada policy SELECT untuk pemilik order. `r2-presign` mengizinkan pembacaan `ops/<partner>/<job>/…` dan `jobs/<job>/payment_proof/…` oleh pemilik order. | `20261116162000_customer_photo_access.sql`, `r2-presign/index.ts` |
| 7 | Pendaftaran bengkel berdokumen selalu ditolak; OTP WhatsApp tidak terkirim | Jalur unggah memakai scope `partnerApplication` (`<uid>/partner-applications/<doc_type>/…`) yang dicocokkan ulang saat pengajuan, bukan `partnerDocs` yang menuntut keanggotaan. OTP dikirim setelah tombol Submit, melalui antrean `notification_outbox`. | `r2_storage.dart`, `r2-presign/index.ts`, `submit-partner-application` |
| 8 | Bot WhatsApp membuat order dengan estimasi palsu | `run_vision_estimation` melempar `EstimationUnavailable`; pipeline berhenti dan meng informing pelanggan bahwa estimasi belum tersedia. Tidak ada lagi total karangan bila AI gagal; harga yang belum diketahui tampil sebagai "Harga menyusul". | `scripts/whatsapp_booking_pipeline.py` |

## P1

| # | Temuan | Perbaikan | Lokasi |
|---|---|---|---|
| 9 | Menu admin tertukar | Konten dipetakan berdasarkan label menu, bukan indeks, sehingga "Workshop Settings & Quotas" dan "Assign Jobs Hub" membuka halaman yang benar. | `master_admin_desktop.dart` |
| 10 | Jadwal dan kapasitas bengkel gagal disimpan | `partner_update_capacity` menyimpan `jsonb` ke kolom `integer[]`/`date[]` dan menulis kolom `updated_at` yang tidak pernah ada — dua-duanya membatalkan simpanan. Sekarang tipe cocok dan ada `partner_get_capacity` untuk dibaca. | `20261116167000_partner_schedule_save.sql`, `schedule_config_screen.dart` |
| 11 | Pemilik bisa memajukan pekerjaan tanpa foto | Trigger database menolak `6_in_progress → 7_finished` tanpa foto pengerjaan dan `3_booked → 5_admitted` tanpa foto kondisi kendaraan. Tombol "Advance"/"Admit Vehicle" meminta foto lebih dulu. | `20261116163000_finished_needs_photo.sql`, `20261116170000_admit_needs_photo.sql`, `partner_job_action.dart` |
| 12 | Tidak ada konfirmasi ambil mobil dan rating | Tabel `job_handover_confirmations` + `job_ratings` dengan RPC `customer_confirm_handover` (hanya pemilik order, hanya dari `8_awaiting_delivery`), dan kartu konfirmasi + bintang rating di layar pelacakan. | `20261116169000_customer_handover_rating.sql`, `live_stepper_timeline.dart` |
| 13 | Staf yang ditambahkan pemilik tidak bisa mengubah status order | `add_partner_staff` dipanggil dengan nama parameter yang salah (`staff_email`/`staff_role`), jadi selalu gagal. Diperbaiki ke `p_staff_email`/`p_staff_role`, dan keanggunaan staf kini punya siklus hidup (aktivasi dan pencabutan akses). | `partner_staff_management_screen.dart`, `20261116166000_membership_lifecycle.sql` |
| 14 | Rekening tujuan transfer belum diatur | `payment_config` punya RLS tanpa policy apa pun; sekarang pelanggan boleh membaca dan admin boleh menulis. Tab "Pengaturan Pembayaran" di layar invoice admin lets an admin mengisi rekening tujuan. | `20261116164000_payment_config_policies.sql`, `admin_invoice_review_screen.dart` |
| 15 | Responden langsung terdaftar tanpa persetujuan | Consent dicatat di `consent_records` dengan RPC `record_consent` / `revoke_consent`; ada tembok persetujuan sebelum responden boleh mengirim data, dan mencabut persetujuan menandai kiriman sebagai tidak boleh dilatih. Pelanggan punya menu "Privasi Data". | `20261116168000_ai_learning_consent.sql`, `consent_screen.dart`, `customer_profile_screen.dart` |
| 16 | Bahasa campur; kode status teknis tampil | Satu peta label status (`core/jobs/job_status.dart`) dipakai di semua tampilan, plus teks Indonesia pada tombol dan pesan yang sebelumnya English. | `job_status.dart`, `live_stepper_timeline.dart`, `customer_profile_screen.dart`, `ops_floor_screen.dart`, `admin_partner_profile_screen.dart` |

## P2

| # | Temuan | Perbaikan | Lokasi |
|---|---|---|---|
| 17 | Klaim tanpa dasar ("38+ hub", "99,4%", garansi 24 bulan) | Copy CMS dan FAQ ditulis ulang sesuai keadaan pilot: satu bengkel mitra, tanpa penilaian, tanpa garansi. Badge di landing diganti angka yang bisa dipertanggungjawabkan. | `20261116165000_cms_claims_corrected.sql`, `faq_screen.dart`, `customer_landing_screen.dart` |
| 18 | Tombol dan angka hiasan di admin | Tombol export yang kosong, lonceng notifikasi tanpa aksi, dan tombol "View" dokumen yang tidak melakukan apa-apa: ketiganya diberi aksi nyata atau dihapus. | `ops_matrix.dart`, `top_header.dart`, `admin_partner_profile_screen.dart` |

---

## Yang sengaja tidak berubah

- **Pembayaran online belum ada.** Tidak ada gateway yang terhubung, jadi tombol
  gateway memberi tahu pelanggan bahwa yang tersedia transfer manual. Mock
  settlement hanya boleh dilakukan admin — ini yang dulu membuat pelanggan
  melihat "Payment failed".
- **Belum ada garansi, belum ada SLA, belum ada integrasi asuransi.** Halaman
  About dan FAQ menyatakan itu apa adanya.
- **`auto_assign_settings.match_location` belum diubah.** Sakelar auto-assign
  aktif, tetapi pencocokan lokasi hanya berlaku bila ada bengkel mitra di
  area yang sama.
- **R2 bucket belum punya CORS.** Unggahan lewat browser masih memakai relay
  (`uploadProxy`), sehingga ada batas 6 MB di web. Foto dikompresi sisi klien
  sebelum dikirim.

## Verifikasi

- `deno check` + `deno lint` pada seluruh edge function: bersih.
- `deno test supabase/functions/_shared/`: 38 lulus, 0 gagal.
- `flutter analyze lib`: 0 error.
- `bash scripts/ci/check_migrations.sh`: semua pemeriksaan lulus.
- Semua migrasi di atas sudah diterapkan ke database produksi
  (`ahaospjkkuetkaixwzzz`).
