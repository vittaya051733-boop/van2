# Creates a server-side Maps API key for Cloud Functions (Places/Geocoding/Directions).
# Fixes: "This IP ... is not authorized to use this API key" from placesAutocomplete.
#
# The Browser key (web/index.html) and Android keys MUST NOT be used in GOOGLE_GEOCODING_API_KEY secret.
#
# Usage (interactive — will prompt for secret value):
#   powershell -File scripts\setup-places-server-api-key.ps1
#
# After running, redeploy functions that use the secret:
#   cd scripts
#   .\deploy-self.ps1 -App van2 -Target functions -FunctionName placesAutocomplete -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
#   .\deploy-self.ps1 -App van2 -Target functions -FunctionName placesResolvePlace -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"

$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
$KeyDisplayName = 'van-maps-server-cf'
$SecretName = 'GOOGLE_GEOCODING_API_KEY'

Write-Host ''
Write-Host '=== van2 Places server key (Cloud Functions) ===' -ForegroundColor Cyan
Write-Host "Project: $ProjectId"
Write-Host ''

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  throw 'gcloud CLI not found. Install Google Cloud SDK first.'
}
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  throw 'firebase CLI not found.'
}

Write-Host '1) Enabling APIs...' -ForegroundColor Yellow
gcloud services enable `
  places-backend.googleapis.com `
  geocoding-backend.googleapis.com `
  directions-backend.googleapis.com `
  --project $ProjectId | Out-Null

Write-Host '2) Creating server API key (no app/referrer restrictions)...' -ForegroundColor Yellow
$createJson = gcloud services api-keys create `
  --display-name=$KeyDisplayName `
  --project=$ProjectId `
  --format=json | ConvertFrom-Json

$keyId = $createJson.uid
if (-not $keyId) {
  throw 'Failed to create API key (missing uid).'
}
Write-Host "   Key id: $keyId" -ForegroundColor DarkGray

Write-Host '3) Restricting to Places + Geocoding + Directions only...' -ForegroundColor Yellow
gcloud services api-keys update $keyId `
  --project=$ProjectId `
  --api-target=service=places-backend.googleapis.com `
  --api-target=service=geocoding-backend.googleapis.com `
  --api-target=service=directions-backend.googleapis.com | Out-Null

Write-Host '4) Reading key string...' -ForegroundColor Yellow
$keyString = gcloud services api-keys get-key-string $keyId --project=$ProjectId --format='value(keyString)'
if (-not $keyString) {
  throw 'Could not read key string.'
}

Write-Host '5) Updating Firebase secret GOOGLE_GEOCODING_API_KEY...' -ForegroundColor Yellow
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$van2Root = Split-Path -Parent $scriptRoot
Push-Location $van2Root
try {
  $keyString | firebase functions:secrets:set $SecretName --project $ProjectId
}
finally {
  Pop-Location
}

Write-Host ''
Write-Host '[ok] Server key created and secret updated.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next: redeploy Cloud Functions (each name separately):' -ForegroundColor Yellow
Write-Host '  placesAutocomplete, placesResolvePlace, computeRouteMetrics, reverseGeocodeDeliveryLocation'
Write-Host ''
Write-Host 'Wait 1-2 minutes after deploy, then retry travel search on Android (logged in).' -ForegroundColor Green
Write-Host ''
