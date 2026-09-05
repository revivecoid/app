$ErrorActionPreference = "Stop"

Write-Host "Stashing changes..."
git stash

Write-Host "Checking out gh-pages..."
git fetch origin gh-pages
git checkout gh-pages
git pull origin gh-pages

Write-Host "Removing bad files..."
git rm -rf temp_gh_pages
git rm -rf ios
git rm -rf supabase
git rm -rf .dart_tool

Write-Host "Committing and pushing..."
git config user.email "bot@antigravity.dev"
git config user.name "Antigravity"
git commit -m "Fix: Remove invalid submodule temp_gh_pages breaking GitHub Actions"
git push origin gh-pages

Write-Host "Checking out main..."
git checkout main
git stash pop
