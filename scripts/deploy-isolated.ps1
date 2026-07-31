param(
  [switch]$FunctionsOnly,
  [switch]$HostingOnly,
  [switch]$StorageOnly,
  [switch]$BuildWeb,
  [string[]]$FunctionName,
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$expectedProjectId = 'van-merchant'
$functionsCodebase = 'van2'
$hostingTarget = 'van2'

$storageScript = Join-Path $scriptRoot 'deploy-storage-isolated.ps1'

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

$expectedConfirmation = "APPROVE:van2:$expectedProjectId"
if ($ConfirmDeploy -ne $expectedConfirmation) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmDeploy '$expectedConfirmation'"
  exit 1
}
Write-Host "[guard] Confirmation accepted: $expectedConfirmation" -ForegroundColor Green

$modeCount = @($FunctionsOnly, $HostingOnly, $StorageOnly).Where({ $_ }).Count
if ($modeCount -eq 0) {
  Write-Error @"
Deployment blocked: combined deploy disabled (protects van3 rider connections).
Specify exactly one mode:
  -StorageOnly   deploy van2 storage rules only (SELF)
  -HostingOnly   deploy van2 hosting only (SELF)
  -FunctionsOnly -FunctionName <name>   deploy one function (SELF)
For shared Firestore: van2\scripts\deploy-self.ps1 -App van2 -Target firestore
"@
  exit 1
}
if ($modeCount -gt 1) {
  Write-Error 'Deployment blocked: specify only ONE of -StorageOnly, -HostingOnly, -FunctionsOnly.'
  exit 1
}

$expectedFile = 'firebase.json'
$expectedImpact = 'SELF:van2'
if ($StorageOnly) {
  $expectedFile = 'storage.rules'
  $expectedImpact = 'SELF:van2'
} elseif ($FunctionsOnly) {
  $expectedFile = 'functions'
  $expectedImpact = 'SELF:van2'
}
if ($ConfirmFile -ne $expectedFile) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmFile '$expectedFile'"
  exit 1
}
if ($ConfirmImpact -ne $expectedImpact) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmImpact '$expectedImpact'"
  exit 1
}
Write-Host "[guard] File confirmation accepted: $expectedFile" -ForegroundColor Green
Write-Host "[guard] Impact confirmation accepted: $expectedImpact" -ForegroundColor Green

if ($InteractiveConfirm) {
  $interactiveFile = Read-Host "Interactive confirm file scope (expected: $expectedFile)"
  if ($interactiveFile -ne $expectedFile) {
    Write-Error "Interactive confirmation failed for file scope."
    exit 1
  }
  $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $expectedImpact)"
  if ($interactiveImpact -ne $expectedImpact) {
    Write-Error "Interactive confirmation failed for impact scope."
    exit 1
  }
  Write-Host "[interactive] File and impact confirmations accepted." -ForegroundColor Green
  $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: YES I UNDERSTAND)"
}

$expectedFinalAcknowledge = 'YES I UNDERSTAND'
if ($FinalAcknowledge -ne $expectedFinalAcknowledge) {
  Write-Error "Deployment blocked. Re-run with: -FinalAcknowledge '$expectedFinalAcknowledge'"
  exit 1
}
Write-Host "[guard] Final acknowledgement accepted." -ForegroundColor Green

$targets = @()

if ($StorageOnly) {
  & $storageScript -ConfirmDeploy $ConfirmDeploy -ConfirmFile 'storage.rules' -ConfirmImpact 'SELF:van2' -FinalAcknowledge $FinalAcknowledge -DryRun:$DryRun
  exit $LASTEXITCODE
}

if ($FunctionsOnly) {
  if (-not $FunctionName -or $FunctionName.Count -eq 0) {
    Write-Error "Functions deploy is locked to explicit function names. Use: scripts/deploy-isolated.ps1 -FunctionsOnly -FunctionName verifyTopUpSlip"
    exit 1
  }

  foreach ($name in $FunctionName) {
    $cleanName = [string]$name
    $cleanName = $cleanName.Trim()
    if (-not $cleanName) {
      continue
    }
    if ($cleanName -notmatch '^[A-Za-z0-9_-]+$') {
      Write-Error "Invalid function name '$cleanName'."
      exit 1
    }
    $targets += "functions:${functionsCodebase}:${cleanName}"
  }

  if ($targets.Count -eq 0) {
    Write-Error 'No valid function names were provided.'
    exit 1
  }

  $env:FUNCTIONS_DISCOVERY_TIMEOUT = '30000'
} elseif ($HostingOnly) {
  $targets += "hosting:$hostingTarget"
}

if ($targets -contains "hosting:$hostingTarget") {
  $hostingMap = $rc.targets.$expectedProjectId.hosting.$hostingTarget
  if (-not $hostingMap -or $hostingMap.Count -eq 0) {
    Write-Error "Hosting target '$hostingTarget' is not mapped. Run: firebase target:apply hosting $hostingTarget <SITE_ID> --project $expectedProjectId"
    exit 1
  }
  if ($BuildWeb) {
    & (Join-Path $PSScriptRoot 'build-web.ps1')
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }
}

Write-Host "Deploying isolated targets: $($targets -join ', ')" -ForegroundColor Cyan
if ($DryRun) {
  Write-Host "[dry-run] Skipping firebase deploy for targets: $($targets -join ', ')" -ForegroundColor Yellow
  return
}
firebase deploy --project $expectedProjectId --only ($targets -join ',')
