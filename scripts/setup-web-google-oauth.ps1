# Registers van*.web.app on the Firebase/Google web OAuth client (fixes "no registered origin").
# Requires: gcloud auth login with project editor/owner on van-merchant
#
# Manual fallback (Console):
# https://console.cloud.google.com/apis/credentials/oauthclient/802503541368-0tg37vm56t3mvuokacoc8idm9mgj0no8.apps.googleusercontent.com?project=van-merchant
# Add Authorized JavaScript origins:
#   https://van1.web.app
#   https://van2.web.app
#   https://van3.web.app
#   https://van4.web.app

$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
$ClientNumber = '802503541368-0tg37vm56t3mvuokacoc8idm9mgj0no8'
$ClientResource = "projects/$ProjectId/brands/-/identityAwareProxyClients/$ClientNumber"
$Origins = @(
  'https://van1.web.app',
  'https://van2.web.app',
  'https://van3.web.app',
  'https://van4.web.app',
  'https://van-merchant.firebaseapp.com',
  'https://van-merchant.web.app'
)
$Redirects = @(
  'https://van1.web.app/__/auth/handler',
  'https://van2.web.app/__/auth/handler',
  'https://van3.web.app/__/auth/handler',
  'https://van4.web.app/__/auth/handler',
  'https://van-merchant.firebaseapp.com/__/auth/handler'
)

$token = gcloud auth print-access-token 2>$null
if (-not $token) {
  throw 'Run: gcloud auth login'
}

Write-Host 'Patching OAuth web client JavaScript origins via Cloud Console API...' -ForegroundColor Cyan

# Classic OAuth client update (Credentials API)
$clientId = "$ClientNumber.apps.googleusercontent.com"
$getUri = "https://content.googleapis.com/oauth2/v2/client/$clientId"
$headers = @{ Authorization = "Bearer $token" }

try {
  $existing = Invoke-RestMethod -Method Get -Uri $getUri -Headers $headers
} catch {
  Write-Host '[warn] Could not read OAuth client via API. Use Console link in script header.' -ForegroundColor Yellow
  Write-Host $_.Exception.Message
  exit 1
}

$jsOrigins = [System.Collections.Generic.HashSet[string]]::new([string[]]@($existing.javascript_origins))
$redirectUris = [System.Collections.Generic.HashSet[string]]::new([string[]]@($existing.redirect_uris))
foreach ($origin in $Origins) { [void]$jsOrigins.Add($origin) }
foreach ($redirect in $Redirects) { [void]$redirectUris.Add($redirect) }

$body = @{
  client_id = $clientId
  javascript_origins = @($jsOrigins)
  redirect_uris = @($redirectUris)
} | ConvertTo-Json

Invoke-RestMethod -Method Put -Uri $getUri -Headers $headers -Body $body -ContentType 'application/json'
Write-Host "[ok] OAuth client updated: $clientId" -ForegroundColor Green
