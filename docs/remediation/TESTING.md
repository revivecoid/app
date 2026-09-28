# TESTING — Cara menjalankan test

## Persyaratan

- Docker Desktop (untuk Supabase CLI lokal)
- Node.js / npx (`G:/PortableHermes/node/`)
- Flutter SDK (`G:/Flutter/flutter/`)
- Git Bash tersedia

## Supabase — test database lokal

```bash
cd G:/AntigravityPortable/.gemini/antigravity/scratch/re-V

# 1. Jalankan stack lokal (pertama kali ~2 menit)
npx supabase start

# 2. Reset DB dan terapkan semua migrasi
npx supabase db reset

# 3. Jalankan seluruh test pgTAP
npx supabase test db

# 4. Reset kembali sebelum test berikutnya
npx supabase db reset && npx supabase test db
```

## Flutter — analyze dan test

```bash
cd G:/AntigravityPortable/.gemini/antigravity/scratch/re-V

# Generate l10n dulu (CI melakukan ini sebelum analyze)
G:/Flutter/flutter/bin/flutter.bat gen-l10n

# Analyze (errors = gagal; warnings/infos = boleh)
G:/Flutter/flutter/bin/flutter.bat analyze --no-fatal-warnings --no-fatal-infos

# Test unit/widget
G:/Flutter/flutter/bin/flutter.bat test
```

## Deno — check Edge Function

```bash
# Dari root repo
deno check supabase/functions/vision-estimation/index.ts
deno check supabase/functions/send-notification/index.ts
deno check supabase/functions/approve-partner/index.ts
deno check supabase/functions/submit-partner-application/index.ts
```

## Status bucket revive-photos (B-06)

Cek status Public bucket:
```bash
curl -s -o /dev/null -w "%{http_code}" \
  https://ahaospjkkuetkaixwzzz.supabase.co/storage/v1/object/public/revive-photos/
```
- `200` = bucket masih publik (**harus diperbaiki di Fase 2**)
- `400`/`403` = bucket sudah private (OK)

**Hasil cek produksi:** _(pemilik repo isi di sini sebelum Fase 2)_
- Tanggal cek: ___
- Status: ___

## Query utilitas

### Cek status bucket langsung
```sql
SELECT id, public, file_size_limit, created_at FROM storage.buckets ORDER BY id;
```

### Cek semua policy dengan sumber terlarang (user_metadata / app_metadata / profiles)
```sql
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE coalesce(qual,'') || coalesce(with_check,'') ~* '(user_metadata|app_metadata|profiles)';
```

### Cek fungsi yang masih baca sumber terlarang
```sql
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND pg_get_functiondef(p.oid) ~* '(user_metadata|app_metadata|profiles\.role|profiles\.partner_id|FROM\s+(public\.)?profiles)';
```

### Cek tabel tanpa RLS atau tanpa policy
```sql
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       count(p.policyname) AS policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policies p ON p.schemaname = n.nspname AND p.tablename = c.relname
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY c.relname, c.relrowsecurity
ORDER BY c.relname;
```

### Cek fungsi SECURITY DEFINER tanpa search_path
```sql
SELECT proname, proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true
  AND (p.proconfig IS NULL OR NOT ('search_path=public,pg_temp' = ANY(p.proconfig)));
```
