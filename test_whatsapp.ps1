$phoneNumberId = "1343952102130566"
$accessToken = "EAAVyAD4nK2wBSUhB172fBnfJHRcX8yKGnZCWFvBAhNOQd8QQ1XduZCZAD4BTkxDoCbax1ZBamkPZAStDS3GHyxk1PWwP5IiQjpZAEiBwcyyfRjqAFpeDYPFPWXPZCKZBcyggGD921eXrwWBEf6ZClrjitQuAk5VfL32O12DXYJLT1t0L2dJZAoIE4JyFigIz3DrzaL85Bfy8AqADXdT63QkP8k94kzkkQzmvMYKaSI3QOMwx6ZA93SbbYdceOpsVNdhB1jdNGSNWx5ZBTDu1DBgdN5m8nZCYILQZDZD"

# REPLACE THIS WITH YOUR VERIFIED TEST PHONE NUMBER (include country code, e.g., 6281122231235)
$toNumber = "6281122231235" 

$url = "https://graph.facebook.com/v19.0/$phoneNumberId/messages"

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# This matches the Edge Function's exact template request
$body = @{
    messaging_product = "whatsapp"
    to = $toNumber
    type = "template"
    template = @{
        name = "booking_status_update"
        language = @{ code = "id" }
        components = @(
            @{
                type = "body"
                parameters = @(
                    @{ type = "text"; text = "John Doe" },
                    @{ type = "text"; text = "Mobil Diterima" },
                    @{ type = "text"; text = "Mobil Anda telah masuk ke bengkel dan sedang diperiksa." }
                )
            }
        )
    }
} | ConvertTo-Json -Depth 10

Write-Host "Sending test WhatsApp message to $toNumber..."
try {
    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
    Write-Host "Success!" -ForegroundColor Green
    $response | ConvertTo-Json | Write-Host
} catch {
    Write-Host "Failed to send message." -ForegroundColor Red
    $_.ErrorDetails.Message | Write-Host
}
