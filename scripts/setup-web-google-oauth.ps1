# Fixes Google Sign-In "no registered origin" / 401 invalid_client on van*.web.app.
# Google Cloud has NO public API for OAuth web-client JavaScript origins — edit in Console once.
#
# Usage:
#   scripts\setup-web-google-oauth.ps1           # print checklist + open Console tabs
#   scripts\setup-web-google-oauth.ps1 -OpenOnly # open Console only

param(
  [switch]$OpenOnly
)

$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
$ClientNumber = '802503541368-0tg37vm56t3mvuokacoc8idm9mgj0no8'
$ClientId = "$ClientNumber.apps.googleusercontent.com"

$OAuthConsoleUrl = "https://console.cloud.google.com/apis/credentials/oauthclient/$ClientNumber.apps.googleusercontent.com?project=$ProjectId"
$AuthDomainsUrl = "https://console.firebase.google.com/project/$ProjectId/authentication/settings"

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

Write-Host ''
Write-Host 'Google Sign-In on web requires ONE-TIME Console setup (no public API).' -ForegroundColor Cyan
Write-Host "OAuth web client: $ClientId" -ForegroundColor DarkGray
Write-Host ''

Write-Host '1) Google Cloud → Credentials → OAuth 2.0 Web client' -ForegroundColor Yellow
Write-Host "   $OAuthConsoleUrl"
Write-Host '   Add Authorized JavaScript origins:' -ForegroundColor White
foreach ($origin in $Origins) { Write-Host "     $origin" }
Write-Host '   Add Authorized redirect URIs:' -ForegroundColor White
foreach ($redirect in $Redirects) { Write-Host "     $redirect" }
Write-Host ''

Write-Host '2) Firebase → Authentication → Settings → Authorized domains' -ForegroundColor Yellow
Write-Host "   $AuthDomainsUrl"
Write-Host '   Ensure these domains exist:' -ForegroundColor White
Write-Host '     van1.web.app'
Write-Host '     van2.web.app'
Write-Host '     van3.web.app'
Write-Host '     van4.web.app'
Write-Host ''

Write-Host '3) Wait ~1–5 minutes, then hard-refresh https://van2.web.app (Ctrl+Shift+R) and retry Google sign-in.' -ForegroundColor Green
Write-Host ''

Start-Process $OAuthConsoleUrl
Start-Sleep -Milliseconds 800
Start-Process $AuthDomainsUrl

if ($OpenOnly) {
  exit 0
}
