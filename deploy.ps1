$ErrorActionPreference = "Stop"
Write-Host "Building flutter web..."
flutter build web --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$hash = (Get-FileHash -Algorithm MD5 build\web\main.dart.js).Hash.Substring(0,8).ToLower()
(Get-Content build\web\flutter_service_worker.js) -replace '"\w{32}"', "`"$hash`"" | Set-Content build\web\flutter_service_worker.js
(Get-Content build\web\flutter_bootstrap.js) -replace 'serviceWorkerVersion: "\d+"', "serviceWorkerVersion: `"$hash`"" | Set-Content build\web\flutter_bootstrap.js
(Get-Content build\web\flutter_bootstrap.js) -replace '"mainJsPath":"main\.dart\.js"', "`"mainJsPath`":`"main.dart.js?v=$hash`"" | Set-Content build\web\flutter_bootstrap.js
(Get-Content build\web\index.html) -replace 'flutter_bootstrap\.js\?v=\w+', "flutter_bootstrap.js?v=$hash" | Set-Content build\web\index.html
Copy-Item -Path build\web\index.html -Destination build\web\404.html -Force

Set-Location build\web
Set-Content -Path CNAME -Value "revive.co.id"
Set-Content -Path .nojekyll -Value ""
if (Test-Path .git) { Remove-Item -Recurse -Force .git }
git init
git checkout -b gh-pages
git config user.email "bot@antigravity.dev"
git config user.name "Antigravity"
git add .
git commit -m "Deploy: Live Update"
# It relies on the parent's credential helper/token to push to the real repo!
$originUrl = (git -C ..\.. config --get remote.origin.url)
git remote add origin $originUrl
git push origin gh-pages --force
Set-Location ..\..
Write-Host "Deploy successful!"
