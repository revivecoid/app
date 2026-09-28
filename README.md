# re-V / Revive

Platform pemesanan dan pelacakan perbaikan bodi kendaraan — menghubungkan pelanggan, bengkel mitra, dan admin operasional.

**Live:** https://revive.co.id

---

## Arsitektur

```
Flutter Web (CanvasKit, hash routing, Riverpod, go_router)
    │
    ├── Supabase (Postgres + RLS + Realtime + Storage + Auth)
    │       ├── Edge Functions (Deno): vision-estimation, send-notification,
    │       │   approve-partner, submit-partner-application, sync-holidays
    │       └── Storage bucket: revive-photos (private), partner-docs (private)
    │
    └── AI cascade: Google Gemini → Groq → OpenRouter (via ai_config table)
```

**Tiga sisi aplikasi:** Pelanggan · Mitra (bengkel) · Admin re-V

---

## Setup lokal

### Prasyarat
- Flutter 3.44.7
- Node.js / npx (untuk Supabase CLI)
- Docker Desktop (untuk Supabase lokal)

### Langkah

```bash
git clone https://github.com/revivecoid/app
cd app

# 1. Buat file .env
cat > .env << 'EOF'
SUPABASE_URL=https://ahaospjkkuetkaixwzzz.supabase.co
SUPABASE_ANON_KEY=<anon_key>
EOF
cp .env assets/.env

# 2. Install dependencies
flutter pub get
flutter gen-l10n

# 3. Jalankan
flutter run -d chrome
```

### Database lokal (opsional)

```bash
npx supabase start        # docker required
npx supabase db reset     # terapkan semua migrasi
npx supabase test db      # jalankan test pgTAP
```

---

## Migrasi

Migrasi ada di `supabase/migrations/`. Tidak ada migration history otomatis — diterapkan manual via Supabase Dashboard → SQL Editor.

Aturan:
- Nama: `YYYYMMDDHHMMSS_nama.sql` (14-digit timestamp unik)
- Idempoten: pakai `IF EXISTS` / `IF NOT EXISTS` / `CREATE OR REPLACE`
- Tidak boleh: `user_metadata`, BOM, `DO $ $` (gunakan `DO $$`)
- Validator: `bash scripts/ci/check_migrations.sh`

---

## Test

```bash
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
npx supabase test db          # butuh supabase start
deno check supabase/functions/vision-estimation/index.ts
```

---

## Rilis

**Satu-satunya jalur rilis: push ke `main`.**

PR → CI hijau (`app` + `functions` + `migrations`) → merge → GitHub Actions deploy ke `gh-pages` → live di revive.co.id

Workflow: `.github/workflows/ci.yml` (gate) + `.github/workflows/deploy.yml` (build+publish)

---

## Peta modul

```
lib/
├── core/              # Theme, routing, utils, shared widgets
│   ├── widgets/       # SignedImage, RevAppBar, ...
│   └── utils/         # auth_url, guest_session, storage_url, ...
├── features/
│   ├── customer_app/  # Estimator, booking, tracking, profil
│   ├── partner_dashboard/  # Job board, profil bengkel, staf, ops
│   ├── admin_central/ # CRM, partner approval, user management, CMS
│   └── cms/           # Content studio, digital asset manager
supabase/
├── migrations/        # Schema + RLS — sumber kebenaran skema
├── functions/         # Edge Functions (Deno)
└── tests/             # pgTAP test suite
docs/remediation/      # Audit & remediation progress
```

---

## Alur status job

`2_estimated → 3_booked → 5_admitted → 3_inspected → 4_paid → 6_in_progress → 7_finished → 8_awaiting_delivery → 9_done`

Angka awalan bukan urutan. Transisi dikontrol server via `advance_job_status` RPC.

---

## Variabel lingkungan

| Variabel | Keterangan |
|---|---|
| `SUPABASE_URL` | Project URL Supabase |
| `SUPABASE_ANON_KEY` | Anon/public key |

Edge Function secrets (Supabase Dashboard → Settings → Edge Functions):
`GOOGLE_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `NOTIFICATION_SHARED_SECRET`
