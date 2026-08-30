# Google Maps on van*.web.app — HTTP referrer setup (Console only; no public API).
#
# Symptom: gray map, "This page can't load Google Maps correctly",
# RefererNotAllowedMapError, or error banner that disappears when Flutter loads.

$ProjectId = 'van-merchant'
$MapsJsKey = 'AIzaSyB6Q5DE_VkpqO3qTn3bqPBawQjxzGEngxY'
$CredentialsUrl = "https://console.cloud.google.com/apis/credentials?project=$ProjectId"

Write-Host ''
Write-Host 'Google Maps web — one-time Console setup' -ForegroundColor Cyan
Write-Host "Project: $ProjectId" -ForegroundColor DarkGray
Write-Host "Maps JS key (web/index.html): $MapsJsKey" -ForegroundColor DarkGray
Write-Host ''
Write-Host '1) APIs & Services → Library — enable if missing:' -ForegroundColor Yellow
Write-Host '   - Maps JavaScript API'
Write-Host '   - Places API'
Write-Host '   - Directions API'
Write-Host '   - Geocoding API'
Write-Host ''
Write-Host '2) APIs & Services → Credentials → edit key above' -ForegroundColor Yellow
Write-Host '   Application restrictions → HTTP referrers (web sites)'
Write-Host '   Add:' -ForegroundColor White
@(
  'https://van1.web.app/*',
  'https://vantalad.web.app/*',
  'https://van3.web.app/*',
  'https://van4.web.app/*',
  'https://van-merchant.web.app/*',
  'https://van-merchant.firebaseapp.com/*',
  'http://localhost:*/*'
) | ForEach-Object { Write-Host "     $_" }
Write-Host ''
Write-Host '   API restrictions → restrict key to Maps JS + Places + Directions + Geocoding' -ForegroundColor White
Write-Host ''
Write-Host '3) Save, wait 1–5 min, hard-refresh https://vantalad.web.app' -ForegroundColor Green
Write-Host ''

Start-Process $CredentialsUrl
