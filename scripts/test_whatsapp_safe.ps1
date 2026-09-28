# WhatsApp Cloud API — Test Script (Safe Version)
# Token dan Phone Number ID dibaca dari variabel lingkungan, TIDAK di-hardcode.
#
# Setup:
#   $env:WHATSAPP_ACCESS_TOKEN = "EAAVy..."   # token dari Meta Business Manager
#   $env:WHATSAPP_PHONE_NUMBER_ID = "134..."  # phone number ID
#   $env:WHATSAPP_TEST_NUMBER = "628..."       # nomor tujuan uji (opsional)
#
# Jalankan:
#   .\scripts\test_whatsapp_safe.ps1

$accessToken     = $env:WHATSAPP_ACCESS_TOKEN
$phoneNumberId   = $env:WHATSAPP_PHONE_NUMBER_ID
$toNumber        = if ($env:WHATSAPP_TEST_NUMBER) { $env:WHATSAPP_TEST_NUMBER } else {
    Write-Error "Set WHATSAPP_TEST_NUMBER env var ke nomor tujuan (mis. 6281122231235)"
    exit 1
}

if (-not $accessToken)   { Write-Error "Set WHATSAPP_ACCESS_TOKEN"; exit 1 }
if (-not $phoneNumberId) { Write-Error "Set WHATSAPP_PHONE_NUMBER_ID"; exit 1 }

$url = "https://graph.facebook.com/v19.0/$phoneNumberId/messages"

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

$body = @{
    messaging_product = "whatsapp"
    to                = $toNumber
    type              = "text"
    text              = @{ body = "Test pesan dari re-V (skrip uji)" }
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body
    Write-Host "Berhasil: $($response | ConvertTo-Json)"
} catch {
    Write-Error "Gagal: $($_.Exception.Message)"
    Write-Error $_.ErrorDetails.Message
}
