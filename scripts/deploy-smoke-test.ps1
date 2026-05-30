<#
.SYNOPSIS
  Automated post-deploy smoke test (step 3).

.DESCRIPTION
  1) Firestore rules compile check (firebase deploy --dry-run, no Java)
  2) Rules emulator tests (if Java 21+)
  3) Live production reads (if smoke-test-config.local.json + ADC)

.EXAMPLE
  .\deploy-smoke-test.ps1 -AfterTarget firestore
#>
param(
  [ValidateSet('firestore', 'functions', 'firestore-van4', 'any')]
  [string]$AfterTarget = 'any',

  [switch]$SkipLive,
  [switch]$SkipEmulator,
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

if (-not $Quiet) {
  Write-Host ''
  Write-Host '=== Post-Deploy Smoke Test (step 3) ===' -ForegroundColor Cyan
  Write-Host "After target: $AfterTarget"
  Write-Host ''
}

$needsSmoke = $AfterTarget -in @('firestore', 'functions', 'firestore-van4', 'any')
if (-not $needsSmoke) {
  if (-not $Quiet) {
    Write-Host "SKIP smoke test: target '$AfterTarget' is SELF/low risk." -ForegroundColor DarkYellow
  }
  exit 0
}

$failed = $false

try {
  if ($AfterTarget -in @('firestore', 'firestore-van4', 'any')) {
    Invoke-RulesCompileSmokeTest
  }

  if (-not $SkipEmulator -and $AfterTarget -in @('firestore', 'any')) {
    if (Test-Java21OrNewer) {
      if (-not $Quiet) {
        Write-Host 'Running rules emulator smoke test (Java 21+)...' -ForegroundColor DarkCyan
      }
      Invoke-RulesEmulatorSmokeTest
    }
    elseif (-not $Quiet) {
      Write-Host 'SKIP emulator tests: Java 21+ not found on PATH.' -ForegroundColor Yellow
      Write-Host '  Install JDK 21+, or use Android Studio JBR and set JAVA_HOME before running.' -ForegroundColor DarkYellow
      Write-Host '  Example: $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"' -ForegroundColor DarkGray
    }
  }

  if (-not $SkipLive) {
    if (Test-Path $configLocal) {
      if (-not $Quiet) {
        Write-Host 'Running live Firestore smoke test (production)...' -ForegroundColor DarkCyan
      }
      Invoke-LiveFirestoreSmokeTest
    }
    elseif (-not $Quiet) {
      Write-Host 'Live test skipped — add production UID checks:' -ForegroundColor Yellow
      Write-Host "  copy `"$configExample`" `"$configLocal`""
      Write-Host '  Set riderUid. Auth: gcloud auth application-default login'
    }
  }
}
catch {
  $failed = $true
  Write-Host $_.Exception.Message -ForegroundColor Red
}

if ($failed) {
  Write-Host ''
  Write-Host 'SMOKE TEST FAILED (step 3) — consider rollback' -ForegroundColor Red
  Write-Host ''
  exit 1
}

if (-not $Quiet) {
  Write-Host ''
  Write-Host 'SMOKE TEST PASSED (step 3)' -ForegroundColor Green
  Write-Host ''
}
exit 0
