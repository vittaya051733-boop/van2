# Adds Maps JavaScript API + van*.web.app HTTP referrers to Firebase Browser key
# (AIzaSyB6Q5DE_... in web/index.html). Safe to re-run.

$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
$KeyId = '071cf2f9-b810-4eaa-b1bd-c574f2d2d752'

$Referrers = @(
  'https://van1.web.app/*',
  'https://van2.web.app/*',
  'https://van3.web.app/*',
  'https://van4.web.app/*',
  'https://van-merchant.web.app/*',
  'https://van-merchant.firebaseapp.com/*',
  'http://localhost:*/*',
  'http://127.0.0.1:*/*'
) -join ','

# Existing Firebase Browser targets + Maps JavaScript API (maps-backend).
$ApiTargets = @(
  'firebasedatabase.googleapis.com',
  'firebasehosting.googleapis.com',
  'firebaserules.googleapis.com',
  'sqladmin.googleapis.com',
  'datastore.googleapis.com',
  'fcmregistrations.googleapis.com',
  'firebase.googleapis.com',
  'firebaseappcheck.googleapis.com',
  'firebaseappdistribution.googleapis.com',
  'firebaseapphosting.googleapis.com',
  'firebaseapptesters.googleapis.com',
  'firebasedataconnect.googleapis.com',
  'firebaseinappmessaging.googleapis.com',
  'firebaseinstallations.googleapis.com',
  'firebaseml.googleapis.com',
  'firebaseremoteconfig.googleapis.com',
  'firebaseremoteconfigrealtime.googleapis.com',
  'firebasestorage.googleapis.com',
  'firebasevertexai.googleapis.com',
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'logging.googleapis.com',
  'mlkit.googleapis.com',
  'securetoken.googleapis.com',
  'storage-component.googleapis.com',
  'storage.googleapis.com',
  'vision.googleapis.com',
  'fcm.googleapis.com',
  'cloudapis.googleapis.com',
  'storage-api.googleapis.com',
  'fpnv.googleapis.com',
  'places-backend.googleapis.com',
  'geocoding-backend.googleapis.com',
  'directions-backend.googleapis.com',
  'maps-backend.googleapis.com'
)

Write-Host 'Updating Firebase Browser key for web Maps...' -ForegroundColor Cyan
Write-Host "Key ID: $KeyId" -ForegroundColor DarkGray

$args = @(
  'services', 'api-keys', 'update', $KeyId,
  '--project', $ProjectId,
  '--allowed-referrers', $Referrers
)
foreach ($service in $ApiTargets) {
  $args += '--api-target=service=' + $service
}

& gcloud @args
if ($LASTEXITCODE -ne 0) {
  throw 'gcloud api-keys update failed'
}

Write-Host '[ok] Browser key now includes Maps JavaScript API + van*.web.app referrers' -ForegroundColor Green
Write-Host 'Wait 1-3 minutes, then hard-refresh https://van2.web.app (Ctrl+Shift+R)' -ForegroundColor Yellow
