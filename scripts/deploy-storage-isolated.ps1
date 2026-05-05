$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot


$expectedProjectId = 'van-merchant'
$storageTarget = 'van2'
$rulesFile = 'storage.rules'

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error 'Firebase CLI was not found in PATH.'
  exit 1
}

if (-not (Test-Path '.firebaserc')) {
  Write-Error 'Missing .firebaserc.'
  exit 1
}

if (-not (Test-Path $rulesFile)) {
  Write-Error "Missing rules file: $rulesFile"
  exit 1
}

$rc = Get-Content '.firebaserc' -Raw | ConvertFrom-Json
$projectId = $rc.projects.default
if ($projectId -ne $expectedProjectId) {
  Write-Error "Configured project '$projectId' does not match expected '$expectedProjectId'."
  exit 1
}

$mappedBuckets = $rc.targets.$expectedProjectId.storage.$storageTarget
if (-not $mappedBuckets -or $mappedBuckets.Count -eq 0) {
  Write-Error "Storage target '$storageTarget' is not mapped. Run: firebase target:apply storage $storageTarget <BUCKET_NAME> --project $expectedProjectId"
  exit 1
}

$tempConfig = '.firebase.storage.van2.tmp.json'
$config = @{
  storage = @(
    @{
      target = $storageTarget
      rules = $rulesFile
    }
  )
}
$config | ConvertTo-Json -Depth 6 | Set-Content -Path $tempConfig -Encoding UTF8

try {
  Write-Host "Deploying Storage rules to target '$storageTarget' in project '$expectedProjectId'" -ForegroundColor Cyan
  firebase deploy --project $expectedProjectId --only "storage:$storageTarget" --config $tempConfig
}
finally {
  if (Test-Path $tempConfig) {
    Remove-Item $tempConfig -Force
  }
}
