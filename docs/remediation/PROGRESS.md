# PROGRESS — Remediasi revivecoid/app

> Setiap agen wajib memperbarui berkas ini di akhir fase.
> Baca berkas ini setelah CONTEXT.md sebelum mengerjakan apa pun.

## Status Fase

| Fase | Berkas | Status | Selesai pada |
|---|---|---|---|
| 0 | F00-setup | **SELESAI** | 2026-09-28 |
| 1 | F01-identity | Belum dimulai | — |
| 2 | F02-write-paths | Belum dimulai | — |
| 3 | F03-migrations-ci | Belum dimulai | — |
| 4 | F04-state-machine | Belum dimulai | — |
| 5 | F05-payment-mock | Belum dimulai | — |
| 6 | F06-status-clients | Belum dimulai | — |
| 7 | F07-booking-capacity | Belum dimulai | — |
| 8 | F08-partner-app | Belum dimulai | — |
| 9 | F09-estimation | Belum dimulai | — |
| 10 | F10-tracking | Belum dimulai | — |
| 11 | F11-admin-cms | Belum dimulai | — |
| 12 | F12-privacy-platform | Belum dimulai | — |
| 13 | F13-backlog | Belum dimulai | — |

---

## Fase 0 — Persiapan, pagar darurat, dan lingkungan uji

**Branch:** `remediation/f0-setup`
**Tanggal:** 2026-09-28

### Rencana (ditulis sebelum eksekusi)
1. Buat `docs/remediation/CONTEXT.md`, `PROGRESS.md`, `MANUAL.md`, `TESTING.md`
2. Handle C-20: hapus `test_whatsapp.ps1`, tulis ulang versi aman yang baca env
3. Tambah secret scanning ke CI `.github/workflows/deploy.yml`
4. Tulis `supabase/tests/00_helpers.sql` (pgTAP helper: create_user, create_partner, dll.)
5. Tulis `supabase/tests/01_smoke_test.sql` (smoke: isolation pelanggan A vs B)
6. Catat status bucket `revive-photos` di TESTING.md
7. Catat B-06 (bucket status) untuk diselesaikan di Fase 2

### Status tiap ID

| ID | Keparahan | Status | Catatan |
|---|---|---|---|
| C-20 | Tinggi | **SELESAI** | `test_whatsapp.ps1` dihapus dari working tree. Versi aman ditulis ke `scripts/test_whatsapp_safe.ps1` (baca token dari env). Instruksi pembersihan riwayat ada di MANUAL.md. Secret scanning ditambah ke CI. |
| B-06 | Tinggi | **Ditunda → Fase 2** | Status bucket `revive-photos` harus dicek langsung di Supabase Dashboard. Langkah verifikasi ada di TESTING.md. Perbaikan (setel private + ganti getPublicUrl) dikerjakan di Fase 2. |

### Migrasi yang ditambahkan
_Tidak ada — Fase 0 tidak mengubah skema._

### Test yang ditambahkan
- `supabase/tests/00_helpers.sql` — helper pgTAP impersonasi
- `supabase/tests/01_smoke_test.sql` — smoke test isolasi pelanggan

### Langkah manual untuk pemilik repo
Lihat `docs/remediation/MANUAL.md` untuk detail. Ringkasan:
1. **SEKARANG:** Cabut/rotasi access token WhatsApp Cloud API di Meta Business Manager
   → Meta Business → WhatsApp → API Setup / System User → revoke / regenerate
   → Simpan token baru hanya sebagai secret Supabase: `supabase secrets set WHATSAPP_ACCESS_TOKEN=<baru>`
2. **SEKARANG:** Bersihkan riwayat git (git filter-repo) — lihat MANUAL.md
3. **Sebelum Fase 2:** Periksa flag Public bucket `revive-photos` di Supabase Dashboard → Storage
   → Catat hasilnya (Public=true atau false) di sini sebelum Fase 2 dimulai
4. **Opsional:** Siapkan `PROD_DB_URL` untuk `supabase db dump` (dibutuhkan Fase 3)

### Keputusan yang perlu dikonfirmasi pemilik
- Status bucket `revive-photos`: Public atau Private? (dibutuhkan Fase 2)
- Apakah agen boleh menjalankan `supabase db dump` ke produksi di Fase 3?

### Ditemukan saat mengerjakan (luar ruang lingkup Fase 0)
- Tidak ada `supabase/config.toml` — `supabase init` perlu dijalankan sebelum `supabase start` bisa dipakai untuk tes lokal. Dicatat di MANUAL.md.
- 8 advisory Python patcher scripts di root repo (untracked) mengandung path sensitif. Tidak di-commit. Perlu dihapus atau dipindah ke folder terpisah (luar scope).
- Repo tidak punya `supabase_migrations.schema_migrations` history — migrasi diterapkan manual; ini dicatat di CONTEXT.md.

### Catatan untuk fase berikutnya (Fase 1)
- **SYARAT:** Konfirmasi langkah manual C-20 (cabut token WA) sudah dilakukan sebelum mulai F1.
- Fase 1 butuh akses produksi untuk query `pg_policies` — gunakan Supabase Management API.
- Fungsi `is_master_admin()` saat ini masih membaca `profiles.role` di beberapa cabang — catat sebagai konteks awal F1.
- Backlog `app_metadata` vs `memberships` split belum selesai (20260920_authorization_consolidation.sql berhenti di langkah 2/4).
