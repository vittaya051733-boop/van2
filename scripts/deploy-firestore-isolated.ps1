param(
  [string]$DatabaseId = '(default)'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot


$expectedProjectId = 'van-merchant'
$rulesFile = 'firestore.rules'

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

$tempConfig = '.firebase.firestore.van2.tmp.json'
$config = @{
  firestore = @{
    database = $DatabaseId
    rules = $rulesFile
  }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfig -Encoding UTF8

try {
  Write-Host "Deploying Firestore rules to database '$DatabaseId' in project '$expectedProjectId'" -ForegroundColor Cyan
  firebase deploy --project $expectedProjectId --only firestore --config $tempConfig
}
finally {
  if (Test-Path $tempConfig) {
    Remove-Item $tempConfig -Force
  }
}
