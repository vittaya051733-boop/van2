<#
.SYNOPSIS
  Firestore rules smoke test — pre-deploy gate + post-deploy verification.

.DESCRIPTION
  1) Rules compile check (firebase deploy --dry-run)
  2) Rules emulator tests (Java 21+) — BLOCKING for PreDeploy and PostDeploy
  3) Live production reads (optional, PostDeploy only, NON-BLOCKING)

.EXAMPLE
  # Gate ก่อน deploy (บล็อกถ้า emulator ล้ม)
  .\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PreDeploy

  # หลัง deploy (emulator ล้ม = exit 1; live ล้ม = คำเตือนอย่างเดียว)
  .\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PostDeploy
#>
param(
  [ValidateSet('firestore', 'functions', 'firestore-van4', 'any')]
  [string]$AfterTarget = 'any',

  [ValidateSet('PreDeploy', 'PostDeploy')]
  [string]$Phase = 'PostDeploy',

  [switch]$SkipLive,
  [switch]$SkipEmulator,
  [switch]$AllowSkipEmulator,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

$scriptRoot = $PSScriptRoot
$smokeDir = Join-Path $scriptRoot 'smoke-test'
$packageJson = Join-Path $smokeDir 'package.json'
$configExample = Join-Path $scriptRoot 'smoke-test-config.local.json.example'
$configLocal = Join-Path $scriptRoot 'smoke-test-config.local.json'
$paths = Get-VanGovernanceRoot
$cfg = Get-VanGovernanceConfig

function Get-JavaMajorVersion {
  param([string]$JavaExe = 'java')

  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& $JavaExe -version 2>&1)
  }
  finally {
    $ErrorActionPreference = $previousEap
  }

  if (-not $output -or $output.Count -eq 0) {
    return 0
  }

  $text = $output[0].ToString()
  if ($text -match 'version "(\d+)') {
    return [int]$Matches[1]
  }
  return 0
}

function Resolve-VanEmulatorJava {
  $candidates = [System.Collections.Generic.List[string]]::new()

  if (Get-Command java -ErrorAction SilentlyContinue) {
    $null = $candidates.Add((Get-Command java).Source)
  }

  if ($env:JAVA_HOME) {
    $fromHome = Join-Path $env:JAVA_HOME 'bin\java.exe'
    if (Test-Path $fromHome) {
      $null = $candidates.Add($fromHome)
    }
  }

  $knownPatterns = @(
    'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    'C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe'
    'C:\Program Files\Microsoft\jdk-21*\bin\java.exe'
    'C:\Program Files\Java\jdk-21*\bin\java.exe'
  )
  foreach ($pattern in $knownPatterns) {
    Get-Item $pattern -ErrorAction SilentlyContinue | ForEach-Object {
      $null = $candidates.Add($_.FullName)
    }
  }

  foreach ($javaExe in ($candidates | Select-Object -Unique)) {
    if ((Get-JavaMajorVersion -JavaExe $javaExe) -lt 21) {
      continue
    }

    $binDir = Split-Path $javaExe -Parent
    $homeDir = Split-Path $binDir -Parent
    $env:JAVA_HOME = $homeDir
    $pathParts = @($binDir) + ($env:Path -split ';' | Where-Object { $_ -and ($_ -ne $binDir) })
    $env:Path = ($pathParts -join ';')
    return $true
  }

  return $false
}

function Test-Java21OrNewer {
  if ((Get-JavaMajorVersion) -ge 21) {
    return $true
  }
  return Resolve-VanEmulatorJava
}

function Invoke-RulesCompileSmokeTest {
  if (-not $Quiet) {
    Write-Host 'Running rules compile check (dry-run)...' -ForegroundColor DarkCyan
  }
  Push-Location $paths.Van2Root
  try {
    firebase deploy --project $cfg.ProjectId --only firestore --dry-run 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw 'Firestore rules compile dry-run failed.'
    }
    if (-not $Quiet) {
      Write-Host 'PASS compile: firestore.rules compiles on project' -ForegroundColor Green
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-RulesEmulatorSmokeTest {
  if (-not (Test-Path $packageJson)) {
    throw "Missing smoke test package: $packageJson"
  }
  if (-not (Test-Path (Join-Path $smokeDir 'node_modules'))) {
    if (-not $Quiet) {
      Write-Host 'Installing smoke-test dependencies (first run)...' -ForegroundColor DarkGray
    }
    Push-Location $smokeDir
    try {
      npm install --omit=dev 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        throw 'npm install failed in scripts/smoke-test'
      }
    }
    finally {
      Pop-Location
    }
  }

  Push-Location $smokeDir
  try {
    firebase emulators:exec --project van-smoke-rules-test --only firestore "node rules-emulator-test.js"
    if ($LASTEXITCODE -ne 0) {
      throw 'Rules emulator smoke test failed.'
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-LiveFirestoreSmokeTest {
  if (-not (Test-Path (Join-Path $smokeDir 'node_modules'))) {
    Push-Location $smokeDir
    try {
      npm install --omit=dev 2>&1 | Out-Null
    }
    finally {
      Pop-Location
    }
  }
  Push-Location $smokeDir
  try {
    node live-firestore-test.js
    if ($LASTEXITCODE -ne 0) {
      throw 'Live Firestore smoke test failed.'
    }
  }
  finally {
    Pop-Location
  }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error 'Node.js is required for smoke tests. Install Node 20+.'
  exit 1
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error 'Firebase CLI is required for smoke tests.'
  exit 1
}

$phaseLabel = if ($Phase -eq 'PreDeploy') { 'Pre-Deploy Gate' } else { 'Post-Deploy Verification' }

if (-not $Quiet) {
  Write-Host ''
  Write-Host "=== Firestore Smoke Test ($phaseLabel) ===" -ForegroundColor Cyan
  Write-Host "Phase: $Phase | Target: $AfterTarget"
  Write-Host ''
}

$needsSmoke = $AfterTarget -in @('firestore', 'functions', 'firestore-van4', 'any')
if (-not $needsSmoke) {
  if (-not $Quiet) {
    Write-Host "SKIP smoke test: target '$AfterTarget' is SELF/low risk." -ForegroundColor DarkYellow
  }
  exit 0
}

if ($Phase -eq 'PreDeploy') {
  $SkipLive = $true
}

$compileFailed = $false
$emulatorFailed = $false
$emulatorSkipped = $false
$liveFailed = $false

try {
  if ($AfterTarget -in @('firestore', 'firestore-van4', 'any')) {
    Invoke-RulesCompileSmokeTest
  }
}
catch {
  $compileFailed = $true
  Write-Host $_.Exception.Message -ForegroundColor Red
}

if (-not $compileFailed -and -not $SkipEmulator -and $AfterTarget -in @('firestore', 'any')) {
  if (Test-Java21OrNewer) {
    if (-not $Quiet) {
      Write-Host 'Running rules emulator smoke test (Java 21+)...' -ForegroundColor DarkCyan
    }
    try {
      Invoke-RulesEmulatorSmokeTest
      if (-not $Quiet) {
        Write-Host 'PASS emulator: van1/van2/van3/van4 critical paths' -ForegroundColor Green
      }
    }
    catch {
      $emulatorFailed = $true
      Write-Host $_.Exception.Message -ForegroundColor Red
    }
  }
  elseif ($AllowSkipEmulator) {
    $emulatorSkipped = $true
    if (-not $Quiet) {
      Write-Host 'WARN: emulator skipped (-AllowSkipEmulator). Not recommended for production deploy.' -ForegroundColor Yellow
    }
  }
  else {
    $emulatorFailed = $true
    Write-Host 'BLOCKED: Java 21+ required for emulator smoke test (mandatory gate).' -ForegroundColor Red
    Write-Host '  Install JDK 21+ or set JAVA_HOME to Android Studio JBR, e.g.:' -ForegroundColor DarkYellow
    Write-Host '  $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"' -ForegroundColor DarkGray
  }
}

if (-not $SkipLive -and $Phase -eq 'PostDeploy' -and -not $compileFailed -and -not $emulatorFailed) {
  if (Test-Path $configLocal) {
    if (-not $Quiet) {
      Write-Host 'Running live Firestore smoke test (production, non-blocking)...' -ForegroundColor DarkCyan
    }
    try {
      Invoke-LiveFirestoreSmokeTest
      if (-not $Quiet) {
        Write-Host 'PASS live-firestore: production checks' -ForegroundColor Green
      }
    }
    catch {
      $liveFailed = $true
      Write-Host $_.Exception.Message -ForegroundColor Yellow
      Write-Host 'ADVISORY: Live smoke failed — NOT treated as rules regression (check ADC / smoke-test-config.local.json).' -ForegroundColor Yellow
    }
  }
  elseif (-not $Quiet) {
    Write-Host 'Live test skipped — optional production UID checks:' -ForegroundColor DarkGray
    Write-Host "  copy `"$configExample`" `"$configLocal`""
    Write-Host '  Set riderUid. Auth: gcloud auth application-default login'
  }
}

$blockingFailed = $compileFailed -or $emulatorFailed

if ($blockingFailed) {
  Write-Host ''
  if ($Phase -eq 'PreDeploy') {
    Write-Host 'PRE-DEPLOY GATE FAILED — deploy blocked. Fix rules or emulator before continuing.' -ForegroundColor Red
  }
  else {
    Write-Host 'POST-DEPLOY SMOKE FAILED — consider rollback (see DEPLOY_CONNECTION_SIGNALS.md).' -ForegroundColor Red
  }
  Write-Host ''
  exit 1
}

if (-not $Quiet) {
  Write-Host ''
  if ($Phase -eq 'PreDeploy') {
    Write-Host 'PRE-DEPLOY GATE PASSED — safe to deploy Firestore rules.' -ForegroundColor Green
  }
  else {
    Write-Host 'POST-DEPLOY SMOKE PASSED (emulator authoritative)' -ForegroundColor Green
    if ($liveFailed) {
      Write-Host '  (live test advisory only — no rollback required for ADC/config issues)' -ForegroundColor DarkYellow
    }
  }
  Write-Host ''
}

exit 0
