$ErrorActionPreference = "Stop"

$hash = (Get-FileHash -Algorithm MD5 build\web\main.dart.js).Hash.Substring(0,8).ToLower()
(Get-Content build\web\flutter_service_worker.js) -replace '"\w{32}"', "`"$hash`"" | Set-Content build\web\flutter_service_worker.js
(Get-Content build\web\flutter_bootstrap.js) -replace 'serviceWorkerVersion: "\d+"', "serviceWorkerVersion: `"$hash`"" | Set-Content build\web\flutter_bootstrap.js
(Get-Content build\web\flutter_bootstrap.js) -replace '"mainJsPath":"main\.dart\.js"', "`"mainJsPath`":`"main.dart.js?v=$hash`"" | Set-Content build\web\flutter_bootstrap.js
(Get-Content build\web\index.html) -replace 'flutter_bootstrap\.js\?v=\w+', "flutter_bootstrap.js?v=$hash" | Set-Content build\web\index.html
Copy-Item -Path build\web\index.html -Destination build\web\404.html -Force

if (Test-Path deploy_temp3) {
    Remove-Item -Recurse -Force deploy_temp3
}
git clone . deploy_temp3 --branch gh-pages

Copy-Item -Path build\web\* -Destination deploy_temp3 -Recurse -Force

Set-Location deploy_temp3
Set-Content -Path CNAME -Value "revive.co.id"
Set-Content -Path .nojekyll -Value ""
git config user.email "bot@antigravity.dev"
git config user.name "Antigravity"
git add .
git commit -m "Deploy: Live Update"
git push origin gh-pages
Set-Location ..
Write-Host "Done!"
