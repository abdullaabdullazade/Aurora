# Quick check that Aurora sync is reachable and configured.
# Usage: .\verify_sync.ps1 [-BaseUrl "https://aurora.marcincloud.org"]

param(
    [string]$BaseUrl = "https://aurora.marcincloud.org"
)

$health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
Write-Host "Health:" ($health | ConvertTo-Json -Compress)

try {
    Invoke-RestMethod -Uri "$BaseUrl/sync" -Method Get -ErrorAction Stop
    Write-Host "Sync: unexpected 200 without auth"
    exit 1
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    $body = $_.ErrorDetails.Message
    Write-Host "Sync (no auth): HTTP $code - $body"
    if ($code -eq 503 -and $body -match "not configured") {
        Write-Host ""
        Write-Host "ACTION: Set FIREBASE_PROJECT_ID in server/.env on NAS and restart:"
        Write-Host "  docker compose pull; docker compose up -d"
        exit 1
    }
    if ($code -eq 401) {
        Write-Host "Sync endpoint is configured (auth required)."
        exit 0
    }
    exit 1
}
