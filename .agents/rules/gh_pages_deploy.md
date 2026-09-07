# GitHub Pages Deployment Rules

## CRITICAL: Files That Must NEVER Be Deleted From gh-pages Branch

The following files **must always exist** on the `gh-pages` branch. They are NOT part of
the Flutter build output and will be wiped by a naive `Remove-Item *` + `Copy-Item build/web/*` deploy.
You MUST restore them after every deploy:

| File | Purpose |
|---|---|
| `.env` | Supabase runtime credentials for flutter_dotenv |
| `assets/.env` | Same - flutter_dotenv reads from assets/.env at runtime |
| `.nojekyll` | Tells GitHub Pages NOT to run Jekyll (required so _-prefixed files are served) |
| `CNAME` | Custom domain mapping (reviveco.id) |
| `_redirects` | SPA fallback routing |
| `404.html` | SPA fallback for gh-pages routing |

## Correct Deploy Procedure

ALWAYS use this pattern when deploying to gh-pages:

`powershell
flutter build web --release
git worktree add .deploy-gh-pages gh-pages
Push-Location ".deploy-gh-pages"

# SAVE critical files BEFORE wiping
$env_content = Get-Content ".env" -Raw -ErrorAction SilentlyContinue
$cname_content = Get-Content "CNAME" -Raw -ErrorAction SilentlyContinue
$redirects_content = Get-Content "_redirects" -Raw -ErrorAction SilentlyContinue

# Wipe and copy new build
Get-ChildItem -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
Copy-Item "..\build\web\*" "." -Recurse -Force

# RESTORE critical files
if ($env_content) { $env_content | Set-Content ".env" -NoNewline }
if ($env_content) { New-Item -ItemType Directory -Force "assets" | Out-Null; $env_content | Set-Content "assets/.env" -NoNewline }
if ($cname_content) { $cname_content | Set-Content "CNAME" -NoNewline }
if ($redirects_content) { $redirects_content | Set-Content "_redirects" -NoNewline }
"" | Set-Content ".nojekyll" -NoNewline

git add -A
git commit -m "deploy: <description>"
git push origin gh-pages
Pop-Location
git worktree remove .deploy-gh-pages
`

## Why Blank Page Happens

App initializes Supabase with keys from assets/.env via flutter_dotenv.
If .env / assets/.env is missing, Supabase.initialize() fails silently and renders blank white screen.

## Supabase Credentials (anon - safe to store, RLS enforces access)

SUPABASE_URL=https://ahaospjkkuetkaixwzzz.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFoYW9zcGpra3VldGthaXh3enp6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc4NDMxNTcsImV4cCI6MjEwMzQxOTE1N30.WuoEjL0sk0DLwHGnriq8n4MBtyf_yaOf8EA499-IJvs
