# MANUAL — Langkah yang dikerjakan pemilik repo

> Berkas ini mencatat tindakan yang **tidak boleh dilakukan agen** karena bersifat irreversibel,
> memerlukan kredensial produksi, atau memerlukan hak akses manusia (force-push, deploy, secret).
> Setiap fase menambahkan seksinya sendiri.

---

## Fase 0

### C-20 — Cabut dan rotasi access token WhatsApp Cloud API

**Status:** ⚠️ PERLU TINDAKAN SEGERA

Token WhatsApp Cloud API ter-commit di `test_whatsapp.ps1` sejak commit `ba56a23` (2026-09-06):
- Phone Number ID: `1343952102130566`
- Access Token: `EAAVyAD4nK2w...` (~250 karakter)
- Nomor telepon penguji: `6281122231235`

Token ini identik dengan `WHATSAPP_PHONE_NUMBER_ID` / `WHATSAPP_ACCESS_TOKEN` yang dipakai `send-notification/index.ts`.

**Langkah cabut (HARUS dilakukan sebelum apapun):**
1. Buka Meta Business Manager → WhatsApp → API Setup → System User
2. Temukan token yang dipakai (dengan Phone Number ID `1343952102130566`)
3. Klik Revoke / Delete
4. Generate token baru
5. Simpan token baru sebagai secret Supabase:
   ```
   npx supabase secrets set WHATSAPP_ACCESS_TOKEN=<token_baru> --project-ref ahaospjkkuetkaixwzzz
   npx supabase secrets set WHATSAPP_PHONE_NUMBER_ID=1343952102130566 --project-ref ahaospjkkuetkaixwzzz
   ```

### C-20 — Bersihkan riwayat git

**PERINGATAN: Tindakan ini irreversibel dan memerlukan kolaborator untuk clone ulang.**

```bash
# Install git-filter-repo bila belum ada
pip install git-filter-repo

# Hapus file dari seluruh riwayat
git filter-repo --path test_whatsapp.ps1 --invert-paths

# Force-push semua branch (IRREVERSIBEL)
git push origin --force --all
git push origin --force --tags

# Beritahu semua kolaborator untuk clone ulang dari awal
```

Agen tidak boleh menjalankan langkah ini.

### B-06 — Status bucket revive-photos

**Perlu cek manual:**
1. Buka Supabase Dashboard → Storage → Buckets
2. Cari bucket `revive-photos`
3. Catat apakah flag **Public** menyala (true/false)
4. Tulis hasilnya di `PROGRESS.md` di bawah B-06 sebelum Fase 2 dimulai

Verifikasi cepat via curl:
```bash
# Ganti <ref> dengan ahaospjkkuetkaixwzzz
curl -s -o /dev/null -w "%{http_code}" \
  https://ahaospjkkuetkaixwzzz.supabase.co/storage/v1/object/public/revive-photos/
# Hasil 200 = bucket publik (masalah), 400/403 = sudah private
```

### Setup Supabase CLI lokal (opsional, untuk test lokal)

Repo belum punya `supabase/config.toml`. Untuk menjalankan test lokal:
```bash
cd G:/AntigravityPortable/.gemini/antigravity/scratch/re-V

# Init (tidak menimpa migrations/ atau functions/)
npx supabase init

# Edit supabase/config.toml, set project_id = "ahaospjkkuetkaixwzzz"

# Jalankan local stack (butuh Docker)
npx supabase start
npx supabase db reset
npx supabase test db
```

### Secret scanning (sudah ditambahkan ke CI di Fase 0)

Ditambahkan `gitleaks/gitleaks-action` ke `.github/workflows/deploy.yml`. Scan ini otomatis berjalan di setiap push dan PR, dan gagal bila ada kunci baru yang terdeteksi.

---

## Fase 1 (akan diisi saat Fase 1 selesai)

_Belum ada._

---

## Fase 2 (akan diisi saat Fase 2 selesai)

_Belum ada._
