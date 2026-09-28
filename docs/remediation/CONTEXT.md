# CONTEXT — Remediasi revivecoid/app

> Berkas ini disimpan di repo sebagai `docs/remediation/CONTEXT.md` (dibuat di Fase 0).
> Setiap sesi agen WAJIB membacanya lebih dulu, lalu `docs/remediation/PROGRESS.md`.
> Isinya sengaja ringkas agar konteks sesi tetap lega.

## Produk
re-V (revive.co.id) adalah platform perbaikan bodi mobil dengan tiga sisi:
- **Pelanggan**: estimasi kerusakan dengan AI dari foto, booking bengkel, pembayaran, dan pelacakan.
- **Mitra (bengkel)**: dashboard job, jadwal/kapasitas, staf, aplikasi ops untuk intake/foto tahap/pengantaran.
- **re-V (admin)**: penugasan job, penilaian mitra, CMS harga/konten, konfigurasi AI.

## Stack
- Satu aplikasi Flutter (web CanvasKit, hash routing, go_router, Riverpod StateNotifier) di `lib/`.
- Supabase: Postgres + RLS, RPC `SECURITY DEFINER`, Realtime, Storage, Auth (termasuk sesi anonim).
- Edge Function Deno di `supabase/functions/`: `vision-estimation`, `send-notification`,
  `approve-partner`, `submit-partner-application`, `sync-holidays`.
- Migrasi di `supabase/migrations/`, test SQL di `supabase/tests/`, test Dart di `test/`.
- CI `.github/workflows/deploy.yml` membangun web ke GitHub Pages. Migrasi ke produksi belum lewat CI.

## Alur status job (yang berlaku)
`2_estimated → 3_booked → 5_admitted → 3_inspected → 4_paid → 6_in_progress → 7_finished → 8_awaiting_delivery → 9_done`, ditambah `0_cancelled`.
**Awalan angka BUKAN urutan.** Jangan pernah membandingkan, mengurutkan, atau menyusun daftar `IN (...)` berdasarkan awalan angka.
Sejak Fase 4, urutan dan transisi dibaca dari tabel `job_statuses` dan `job_status_transitions`.

## Peran dan otorisasi
- **Sumber kebenaran tunggal otorisasi adalah tabel `memberships`**
  - Kolom: `user_id, scope ('platform'|'partner'), org_id, role (membership_role), status`.
  - Nilai `membership_role`: `master_admin, customer, owner, mechanic, staff, driver`.
- Fungsi bantu: `is_master_admin()`, `has_partner_membership(org_id, roles[])`, `has_platform_membership(role)`, `get_my_partner_id()`.
- **DILARANG** memakai sumber berikut untuk keputusan akses di SQL maupun Edge Function:
  - `profiles.role`, `profiles.partner_id`
  - `raw_user_meta_data` / `user_metadata`
  - `app_metadata`

  `app_metadata` boleh tetap diisi, tetapi hanya sebagai cache tampilan di klien.
- Kosakata lama `partner_mechanic / partner_staff / partner_driver` masih muncul di kode Dart dan di `app_metadata`.
  - `partner_mechanic` di aplikasi berarti **pemilik bengkel** (owner). Ini diperbaiki di Fase 1.
- **ID bengkel (`partners.id`) BUKAN `auth.uid()`.** Selalu resolusikan lewat `memberships.org_id` atau `get_my_partner_id()`.

## Aturan kerja untuk agen
1. **Satu fase per sesi, satu branch per fase.**
   - Nama branch: `remediation/fN-<slug>`.
   - Jangan mengerjakan temuan di luar daftar fase. Catat temuan baru di `PROGRESS.md` bagian "Ditemukan saat mengerjakan".
2. **Baca hemat.**
   - Buka hanya berkas yang disebut di prompt fase dan pemanggilnya.
   - Untuk berkas besar, cari dulu (grep/rg), lalu baca potongan yang relevan.
3. **Semua perubahan skema lewat migrasi baru.**
   - Nama: `supabase/migrations/YYYYMMDDHHMMSS_<nama>.sql`, dengan timestamp unik dan lebih besar dari migrasi terakhir.
   - Jangan pernah mengedit migrasi lama.
   - Setiap migrasi harus idempoten sejauh wajar (`IF EXISTS` / `IF NOT EXISTS` / `CREATE OR REPLACE`).
4. **Setiap fungsi `SECURITY DEFINER`**:
   - memakai `SET search_path = public, pg_temp`;
   - memanggil `REVOKE EXECUTE ... FROM PUBLIC, anon`;
   - hanya mendapat `GRANT` ke peran yang memang memanggilnya.
5. **Tulisan ke tabel inti hanya lewat RPC.**
   - Tabel inti: `repair_jobs`, `partners`, `memberships`, `payments`, dan status apa pun.
   - Jangan menambah policy INSERT/UPDATE untuk `authenticated` pada kolom yang menentukan uang, status, peran, atau kepemilikan.
6. **Test wajib.**
   - Setiap perbaikan keamanan atau logika disertai test pgTAP di `supabase/tests/` yang **gagal sebelum perbaikan dan lulus sesudahnya**.
   - Perubahan Dart disertai test unit/widget bila logikanya bisa diuji.
   - Jalankan `supabase test db` dan `flutter analyze && flutter test` sebelum selesai.
7. **Jangan menulis teks sukses sebelum server membalas sukses.** Jangan menelan error dengan diam; tampilkan pesan yang bisa dimengerti pengguna dan log detailnya.
8. **Tindakan berikut dilarang untuk agen dan dicatat di `docs/remediation/MANUAL.md` untuk dikerjakan pemilik repo:**
   - deploy ke produksi, `supabase db push` ke produksi;
   - `git push --force`, menghapus riwayat git;
   - mengubah secret.
9. **Akhiri setiap fase dengan tiga hal:**
   - Perbarui `PROGRESS.md`: status tiap ID (Selesai / Sebagian / Ditunda + alasan), migrasi yang ditambahkan, langkah manual, dan catatan untuk fase berikutnya.
   - Buat commit dengan format `fix(fN): <ringkas> [ID, ID, ...]`.
   - Buat ringkasan maksimal 15 baris untuk pemilik repo.

## Pembayaran
**Belum ada payment gateway. Pembayaran adalah MOCK** sampai ada keputusan lain.
- Mock tetap harus aman: status `4_paid` hanya boleh ditulis oleh fungsi settlement di server, **tidak pernah** oleh pelanggan atau klien.
- Semua layar mock diberi label jelas "SIMULASI — tidak ada dana yang ditagih".
- Desainnya harus bisa diganti ke gateway nanti tanpa mengubah alur status (lihat Fase 5).

## Lingkungan uji
Dibuat di Fase 0 dan ditulis di `docs/remediation/TESTING.md`.
- Supabase CLI lokal (Docker): `supabase start`, `supabase db reset`, `supabase test db`.
- Helper impersonasi pgTAP ada di `supabase/tests/00_helpers.sql`:
  - `tests.create_user(email, role)`, `tests.create_partner(owner)`, `tests.add_member(partner, user, role)`, `tests.create_job(customer, status, partner)`
  - `tests.as_user(uuid)`, `tests.as_anon()`, `tests.as_service()`, `tests.reset_role()`

## Referensi temuan
Semua ID berasal dari dokumen "Audit Terpadu revivecoid/app" (commit eb0932e).

| Awalan | Asal |
|---|---|
| SEC/REL/BIZ/DAT/UX/A11Y/I18N/PERF/CODE/PLAT/OPS/SEO/PRIV/QA | Audit pertama |
| B-xx | Audit ulang |
| L/S/D/G | Bug, logika, SSOT |
| C-xx | Sapuan cakupan |

Detail setiap temuan yang dikerjakan sudah disalin ke prompt fase masing-masing.
