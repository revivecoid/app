$ErrorActionPreference = "Stop"
flutter build web --release
Remove-Item -Recurse -Force build\web\.git -ErrorAction Ignore
Remove-Item -Recurse -Force deploy_final -ErrorAction Ignore
New-Item -ItemType Directory -Path deploy_final | Out-Null
Copy-Item -Path build\web\* -Destination deploy_final -Recurse -Force
cd deploy_final
git init
git checkout -b gh-pages
git config user.email "bot@antigravity.dev"
git config user.name "Antigravity"
git add .
git commit -m "Deploy: Booking & Checkout Flow"
# Set GH_PAT env var before running: $env:GH_PAT = "your_token_here"
git remote add origin "https://revivecoid:$env:GH_PAT@github.com/revivecoid/app.git"
git push origin gh-pages --force
cd ..
