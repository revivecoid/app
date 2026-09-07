# deploy_gh_pages.ps1  —  Safe GitHub Pages deploy for re-V Flutter web app.
# Run from repo root: .\deploy_gh_pages.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$WORKTREE = ".deploy-gh-pages"

# 1. Build
Write-Host "[1/5] Building Flutter web..." -ForegroundColor Cyan
flutter build web --release --base-href "/"
if ($LASTEXITCODE -ne 0) { throw "flutter build failed — deploy aborted." }

# 2. Worktree
Write-Host "[2/5] Checking out gh-pages worktree..." -ForegroundColor Cyan
if (Test-Path $WORKTREE) { git worktree remove $WORKTREE --force }
git worktree add $WORKTREE gh-pages
Push-Location $WORKTREE

try {
    # 3. Save critical files BEFORE wipe
    Write-Host "[3/5] Saving critical files..." -ForegroundColor Cyan
    $saved = @{}
    foreach ($f in @(".env","CNAME","_redirects","404.html")) {
        if (Test-Path $f) { $saved[$f] = Get-Content $f -Raw; Write-Host "  Saved $f" -ForegroundColor Green }
        else              { Write-Host "  WARNING: $f not on gh-pages" -ForegroundColor Yellow }
    }

    # 4. Wipe + copy build
    Write-Host "[4/5] Deploying build/web..." -ForegroundColor Cyan
    Get-ChildItem -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
    Copy-Item "..\build\web\*" "." -Recurse -Force

    # 5. Restore critical files
    Write-Host "[5/5] Restoring critical files..." -ForegroundColor Cyan
    if ($saved.ContainsKey(".env")) {
        $saved[".env"] | Set-Content ".env" -NoNewline
        New-Item -ItemType Directory -Force "assets" | Out-Null
        $saved[".env"] | Set-Content "assets/.env" -NoNewline
        Write-Host "  Restored .env + assets/.env" -ForegroundColor Green
    } else {
        throw "CRITICAL: .env was not on gh-pages — cannot restore. Deploy aborted."
    }
    foreach ($f in @("CNAME","_redirects","404.html")) {
        if ($saved.ContainsKey($f)) { $saved[$f] | Set-Content $f -NoNewline; Write-Host "  Restored $f" -ForegroundColor Green }
    }
    "" | Set-Content ".nojekyll" -NoNewline
    Write-Host "  Restored .nojekyll" -ForegroundColor Green

    # Safety check
    foreach ($required in @("assets/.env",".nojekyll","index.html","CNAME")) {
        if (-not (Test-Path $required)) { throw "SAFETY FAIL: $required missing before commit!" }
    }

    # Commit + push
    $hash = (git -C ".." rev-parse --short HEAD)
    git add -A
    git commit -m "deploy: main@$hash"
    git push origin gh-pages
    Write-Host "`nDone! gh-pages updated from main@$hash" -ForegroundColor Green

} finally {
    Pop-Location
    git worktree remove $WORKTREE --force 2>$null
}
