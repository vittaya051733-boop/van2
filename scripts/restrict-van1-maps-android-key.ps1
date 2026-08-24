# Restrict van1 AndroidManifest Maps key (AIzaSyABo43...) for van.merchant package.
# Safe to re-run — preserves debug + upload SHA-1 entries.
$ErrorActionPreference = 'Stop'

$ProjectId = 'van-merchant'
# Maps SDK key in van1 AndroidManifest.xml — GCP name "API key 4"
$KeyId = 'ce8c4d6a-d961-4ddd-9867-44dab3787bd2'
$DebugSha1 = '17:D5:1E:94:74:3C:DD:99:58:BB:43:89:87:6F:EB:67:D6:8E:60:61'
$UploadSha1 = '2B:F4:DA:BD:44:4D:DC:F9:D5:AE:F8:7E:F9:33:04:AA:93:FF:1E:BA'

$AndroidApps = @(
  @{ package = 'van.merchant'; sha1 = $DebugSha1 },
  @{ package = 'van.merchant'; sha1 = $UploadSha1 }
)

$ApiTargets = @(
  'maps-android-backend.googleapis.com'
)

Write-Host 'Restricting van1 Maps SDK key (van.merchant)...' -ForegroundColor Cyan
Write-Host "Key ID: $KeyId (API key 4 — check AndroidManifest ends in ...GsU)" -ForegroundColor DarkGray

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

Write-Host '[ok] van1 Maps key restricted to van.merchant (debug + upload SHA-1)' -ForegroundColor Green
