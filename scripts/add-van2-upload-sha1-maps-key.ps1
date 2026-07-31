# Add van2 upload keystore SHA-1 to Firebase Android Maps API key (safe to re-run).
$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
$KeyId = '3b9e3186-50da-45c8-9d79-22fe437b6672'
$UploadSha1 = '2B:F4:DA:BD:44:4D:DC:F9:D5:AE:F8:7E:F9:33:04:AA:93:FF:1E:BA'
$DebugSha1 = '17:D5:1E:94:74:3C:DD:99:58:BB:43:89:87:6F:EB:67:D6:8E:60:61'

$AndroidApps = @(
  @{ package = 'van.merchant'; sha1 = $DebugSha1 },
  @{ package = 'Van2.com'; sha1 = $DebugSha1 },
  @{ package = 'Van2.com'; sha1 = $UploadSha1 },
  @{ package = 'van3.rider.com'; sha1 = $DebugSha1 }
)

$ApiTargets = @(
  'datastore.googleapis.com',
  'firestore.googleapis.com',
  'logging.googleapis.com',
  'monitoring.googleapis.com',
  'storage.googleapis.com',
  'storage-component.googleapis.com',
  'firebasestorage.googleapis.com',
  'vision.googleapis.com',
  'fcmregistrations.googleapis.com',
  'firebaseappcheck.googleapis.com',
  'firebaseappdistribution.googleapis.com',
  'fcm.googleapis.com',
  'firebasehosting.googleapis.com',
  'firebaseinstallations.googleapis.com',
  'firebaserules.googleapis.com',
  'firebaseremoteconfigrealtime.googleapis.com',
  'firebaseremoteconfig.googleapis.com',
  'firebase.googleapis.com',
  'cloudapis.googleapis.com',
  'storage-api.googleapis.com',
  'securetoken.googleapis.com',
  'serviceusage.googleapis.com',
  'servicemanagement.googleapis.com',
  'cloudaicompanion.googleapis.com',
  'runtimeconfig.googleapis.com',
  'appengine.googleapis.com',
  'dataplex.googleapis.com',
  'sql-component.googleapis.com',
  'testing.googleapis.com',
  'cloudtrace.googleapis.com',
  'identitytoolkit.googleapis.com',
  'fpnv.googleapis.com',
  'maps-android-backend.googleapis.com'
)

Write-Host 'Adding Van2.com upload SHA-1 to Android Maps key...' -ForegroundColor Cyan
Write-Host "Key: $KeyId (AIzaSyCuGZF0-... in AndroidManifest)" -ForegroundColor DarkGray

$args = @('services', 'api-keys', 'update', $KeyId, '--project', $ProjectId)
foreach ($app in $AndroidApps) {
  $args += @(
    '--allowed-application',
    "sha1_fingerprint=$($app.sha1),package_name=$($app.package)"
  )
}
foreach ($service in $ApiTargets) {
  $args += "--api-target=service=$service"
}

& gcloud @args
if ($LASTEXITCODE -ne 0) {
  throw 'gcloud api-keys update failed'
}

Write-Host '[ok] Van2.com upload SHA-1 added (debug entries preserved)' -ForegroundColor Green
Write-Host 'Wait 1-2 minutes before testing release Maps on device.' -ForegroundColor Yellow
