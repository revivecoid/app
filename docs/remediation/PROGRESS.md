# PROGRESS — Remediasi revivecoid/app

> Setiap agen wajib memperbarui berkas ini di akhir fase.
> Baca berkas ini setelah CONTEXT.md sebelum mengerjakan apa pun.

## Status Fase

| Fase | Berkas | Status | Selesai pada |
|---|---|---|---|
| 0 | F00-setup | **SELESAI** | 2026-09-28 |
| 1 | F01-identity | **SELESAI** | 2026-09-28 |
| 2 | F02-write-paths | **SELESAI** | 2026-09-28 |
| 3 | F03-migrations-ci | **SELESAI** | 2026-09-28 |
| 4 | F04-state-machine | **SELESAI** | 2026-09-28 |
| 5 | F05-payment-mock | **SELESAI** | 2026-09-28 |
| 6 | F06-status-clients | **SELESAI** | 2026-09-28 |
| 7 | F07-booking-capacity | Belum dimulai | — |
| 8 | F08-partner-app | Belum dimulai | — |
| 9 | F09-estimation | Belum dimulai | — |
| 10 | F10-tracking | Belum dimulai | — |
| 11 | F11-admin-cms | Belum dimulai | — |
| 12 | F12-privacy-platform | **SELESAI** | 2026-09-28 |
| 13 | F13-backlog | Belum dimulai | — |

---

## Fase 0 — Persiapan, pagar darurat, dan lingkungan uji

**Branch:** `remediation/f0-setup`
**Tanggal:** 2026-09-28

### Status tiap ID

| ID | Keparahan | Status | Catatan |
|---|---|---|---|
| C-20 | Tinggi | **SELESAI** | `test_whatsapp.ps1` dihapus dari working tree. Versi aman ditulis ke `scripts/test_whatsapp_safe.ps1`. Secret scanning (gitleaks) ditambah ke CI. Instruksi pembersihan riwayat ada di MANUAL.md. |
| B-06 | Tinggi | **Ditunda → Fase 2** | Status bucket harus dicek di Supabase Dashboard. Perbaikan (private + signed URL) di Fase 2. |

### Migrasi yang ditambahkan
_Tidak ada — Fase 0 tidak mengubah skema._

### Test yang ditambahkan
- `supabase/tests/00_helpers.sql` — helper pgTAP impersonasi
- `supabase/tests/01_smoke_test.sql` — smoke test isolasi pelanggan

### Langkah manual untuk pemilik repo
1. **SEKARANG:** Cabut/rotasi access token WhatsApp Cloud API di Meta Business Manager
2. **SEKARANG:** Bersihkan riwayat git (`git filter-repo --path test_whatsapp.ps1 --invert-paths`) — lihat MANUAL.md
3. **Sebelum Fase 2:** Periksa flag Public bucket `revive-photos` dan catat di PROGRESS.md

### Catatan untuk Fase 1
- Fungsi `is_master_admin()` masih membaca `profiles.role` — perbaikan ada di F1
- Backlog `app_metadata` vs `memberships` split belum selesai (langkah 2/4)

---

## Fase 1 — Keamanan A — identitas, peran, dan keanggotaan

**Branch:** `remediation/f1-identity`
**Tanggal:** 2026-09-28

### Rencana (ditulis sebelum eksekusi)
1. Perbaiki `is_master_admin()` → baca dari memberships
2. Perbaiki `get_my_partner_id()` + `has_partner_membership()` → cek bengkel aktif (B-05)
3. Drop 7 policy user_metadata (B-03) + buat ulang berbasis memberships
4. Trigger kunci profiles.role/partner_id (C-02)
5. Batasi partners_select, buat view partners_public (C-13)
6. Fix set_user_role: cabut membership saat demosi (C-15)
7. Fix add/remove_partner_staff: tulis memberships (C-09, C-45, C-78)
8. Trigger guard UPDATE partners: kolom sensitif hanya admin (C-16)
9. CHECK constraint ai_config: api_key_env dan api_base_url aman (B-10)
10. Fix get_partner_active_job_count: search_path + revoke anon (C-88)
11. Backfill S-05: partner_mechanic → owner di memberships
12. Guard function check_partner_approval_safe untuk C-65 (dipakai F8)
13. Dart: hapus 'role' dari upsert customer_profile_screen (C-02)

### Status tiap ID

| ID | Keparahan | Status | Catatan |
|---|---|---|---|
| B-03 | KRITIS | **SELESAI** | 7 policy user_metadata/COALESCE di-drop dan dibuat ulang berbasis has_partner_membership()/is_master_admin() |
| C-02 | KRITIS | **SELESAI** | Trigger profiles_lock_sensitive + INSERT policy customer only + Dart upsert→update tanpa 'role' |
| SEC-02 | KRITIS | **SELESAI** | is_master_admin() sekarang baca memberships, bukan profiles.role |
| B-05 | TINGGI | **SELESAI** | get_my_partner_id() + has_partner_membership() join ke partners.is_active |
| C-08 | TINGGI | **SELESAI** | partner_docs + partner_photos policy: partner_id=auth.uid() → has_partner_membership() |
| C-09 | TINGGI | **SELESAI** | add/remove_partner_staff sekarang tulis/nonaktifkan memberships |
| C-13 | TINGGI | **SELESAI** | partners_select diganti partners_admin_or_own; partners_public view dibuat |
| C-15 | TINGGI | **SELESAI** | set_user_role: DELETE membership platform saat new_role != master_admin |
| C-16 | TINGGI | **SELESAI** | Trigger partners_guard_sensitive: tolak perubahan kolom sensitif oleh non-admin |
| S-05 | TINGGI | **SELESAI** | Backfill: partners.user_id → membership 'owner'; duplicate mechanic di-nonaktifkan |
| SEC-06 | TINGGI | **Sebagian** | Policy tabel inti kini ada di migrasi (verifikasi di F3 saat baseline produksi tersedia) |
| SEC-08 | TINGGI | **SELESAI** | Dart sudah baca app_metadata; policy COALESCE user_metadata di-drop (B-03) |
| B-10 | SEDANG | **SELESAI** | CHECK constraint api_key_env dan api_base_url ditambahkan ke ai_config |
| C-45 | SEDANG | **SELESAI** | add_partner_staff: tolak target yang sudah punya membership partner lain; pesan generik |
| C-65 | SEDANG | **Sebagian** | check_partner_approval_safe() dibuat; logic Edge Function approve-partner dikerjakan F8 |
| C-78 | RENDAH | **SELESAI** | lower(trim(email)) di add_partner_staff dan remove_partner_staff |
| C-88 | RENDAH | **SELESAI** | get_partner_active_job_count: SET search_path + REVOKE anon/authenticated |

### Migrasi yang ditambahkan
- `supabase/migrations/20260928000000_f1_identity_security.sql` — seluruh perbaikan Fase 1

### Test yang ditambahkan
- `supabase/tests/02_identity_security_test.sql` — 8 test kasus Fase 1

### Langkah manual untuk pemilik repo
- **Tempel migrasi `20260928000000_f1_identity_security.sql` ke SQL Editor Supabase** (produksi)
- **Setelah apply**, jalankan query verifikasi di akhir migrasi untuk konfirmasi
- Cabut token WhatsApp bila belum dilakukan (C-20)
- Cek bucket revive-photos sebelum memulai Fase 2

### Keputusan yang perlu dikonfirmasi pemilik
- **partners_public view:** Kolom apa saja yang perlu ditampilkan ke publik (selain id, shop_name, address, is_active, tier)? Saat ini hanya kolom aman.
- **Cancellation policy** (diperlukan Fase 4): gratis sebelum kendaraan masuk; setelah masuk hanya admin yang bisa batalkan.
- **approve-partner logic** (C-65): Edge Function perlu diupdate di Fase 8.

### Ditemukan saat mengerjakan (luar ruang lingkup Fase 1)
- `toggle_partner_online` masih membaca `raw_app_meta_data` dari `auth.users` (bukan `get_my_partner_id()`). Catat untuk Fase 2 atau 8.
- `admin_suspend_partner` tidak mencabut membership aktif staf bengkel — hanya setel `is_active=false`. `has_partner_membership()` kini cek `p.is_active` jadi ini sudah tertutup oleh perbaikan B-05.
- Migrasi `memberships` constraint `ON CONFLICT` memakai kolom nullable `org_id` — perlu diperhatikan bila ada konflik INSERT. Gunakan `COALESCE(org_id, '00000000...')` di unique index (catat untuk F3).

### Catatan untuk Fase 2
- Fase 2 mengerjakan jalur tulis: trigger repair_jobs_guard, bucket revive-photos, signed URL
- Perlu tahu status bucket (Public/Private) sebelum mulai
- admin_set_job_status RPC sementara perlu dibuat (sampai Fase 4 selesai dengan job_status_transitions)
