param(
  [switch]$FunctionsOnly,
  [switch]$HostingOnly,
  [switch]$BuildWeb
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$expectedProjectId = 'van-merchant'
$functionsCodebase = 'van2'
$hostingTarget = 'van2'

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error 'Firebase CLI was not found in PATH.'
  exit 1
}

if (-not (Test-Path '.firebaserc') -or -not (Test-Path 'firebase.json')) {
  Write-Error 'Missing .firebaserc or firebase.json.'
  exit 1
}

$rc = Get-Content '.firebaserc' -Raw | ConvertFrom-Json
$projectId = $rc.projects.default
if ($projectId -ne $expectedProjectId) {
  Write-Error "Configured project '$projectId' does not match expected '$expectedProjectId'."
  exit 1
}

$targets = @()
if ($FunctionsOnly -and -not $HostingOnly) {
  $targets += "functions:$functionsCodebase"
} elseif ($HostingOnly -and -not $FunctionsOnly) {
  $targets += "hosting:$hostingTarget"
} else {
  $targets += "functions:$functionsCodebase"
  $targets += "hosting:$hostingTarget"
}

if ($targets -contains "hosting:$hostingTarget") {
  $hostingMap = $rc.targets.$expectedProjectId.hosting.$hostingTarget
  if (-not $hostingMap -or $hostingMap.Count -eq 0) {
    Write-Error "Hosting target '$hostingTarget' is not mapped. Run: firebase target:apply hosting $hostingTarget <SITE_ID> --project $expectedProjectId"
    exit 1
  }
  if ($BuildWeb) {
    flutter build web
  }
}

Write-Host "Deploying isolated targets: $($targets -join ', ')" -ForegroundColor Cyan
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '30000'
firebase deploy --project $expectedProjectId --only ($targets -join ',')
