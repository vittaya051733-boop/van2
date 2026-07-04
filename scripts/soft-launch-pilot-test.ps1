<#
.SYNOPSIS
  Soft-launch pilot readiness — automated checks + Crashlytics verification guide.

.DESCRIPTION
  1) Tooling prerequisites (Node, Firebase CLI, Java, Flutter)
  2) SDK / google-services.json / Gradle plugin checks for van1–van4
  3) Firestore rules + order lifecycle E2E (emulator)
  4) Key Flutter tests on van2
  5) Optional: launch release build with PILOT_OBSERVABILITY_VERIFY

.EXAMPLE
  .\soft-launch-pilot-test.ps1

.EXAMPLE
  .\soft-launch-pilot-test.ps1 -SkipEmulator

.EXAMPLE
  .\soft-launch-pilot-test.ps1 -SendObservabilityPing -App van2
#>
param(
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App = 'van2',

  [switch]$SkipEmulator,
  [switch]$SkipFlutterTests,
  [switch]$SendObservabilityPing,
  [switch]$ForceCrashlyticsTestCrash,
  [switch]$Strict,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$van2Root = Split-Path $scriptRoot -Parent
$desktopRoot = Split-Path $van2Root -Parent

$AppMap = @{
  van1 = @{
    Label = 'van1 merchant'
    Dir   = Join-Path $desktopRoot 'van1\my-flutter'
    Package = 'van.merchant'
    ObservabilityName = 'van1_merchant'
  }
  van2 = @{
    Label = 'van2 customer'
    Dir   = $van2Root
    Package = 'Van2.com'
    ObservabilityName = 'van2_customer'
  }
  van3 = @{
    Label = 'van3 rider'
    Dir   = Join-Path $desktopRoot 'van3'
    Package = 'van3.rider.com'
    ObservabilityName = 'van3_rider'
  }
  van4 = @{
    Label = 'van4 admin'
    Dir   = Join-Path $desktopRoot 'van4'
    Package = 'van4.com'
    ObservabilityName = 'van4_admin'
  }
}

$results = [System.Collections.Generic.List[object]]::new()

function Write-Step {
  param([string]$Message)
  if (-not $Quiet) {
    Write-Host "`n== $Message ==" -ForegroundColor Cyan
  }
}

function Add-Result {
  param(
    [string]$Name,
    [bool]$Passed,
    [string]$Detail = '',
    [switch]$Advisory
  )
  $status = if ($Passed) { 'PASS' } else { if ($Advisory) { 'WARN' } else { 'FAIL' } }
  $script:results.Add([pscustomobject]@{
      Check  = $Name
      Status = $status
      Detail = $Detail
    })
  if (-not $Quiet) {
    $color = switch ($status) {
      'PASS' { 'Green' }
      'WARN' { 'Yellow' }
      default { 'Red' }
    }
    $suffix = if ($Detail) { " - $Detail" } else { '' }
    Write-Host ("[{0}] {1}{2}" -f $status, $Name, $suffix) -ForegroundColor $color
  }
}

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
  if (-not $output -or $output.Count -eq 0) { return 0 }
  $text = $output[0].ToString()
  if ($text -match 'version "(\d+)') { return [int]$Matches[1] }
  return 0
}

function Test-AppObservabilityFiles {
  param([hashtable]$Config)

  $dir = $Config.Dir
  $ok = $true
  $details = [System.Collections.Generic.List[string]]::new()

  $obsFile = Join-Path $dir 'lib\services\observability_service.dart'
  if (-not (Test-Path $obsFile)) {
    $ok = $false
    $null = $details.Add('missing observability_service.dart')
  }

  $gs = Join-Path $dir 'android\app\google-services.json'
  if (-not (Test-Path $gs)) {
    $ok = $false
    $null = $details.Add('missing google-services.json')
  }

  $gradle = Join-Path $dir 'android\app\build.gradle.kts'
  if (Test-Path $gradle) {
    $gradleText = Get-Content $gradle -Raw
    if ($gradleText -notmatch 'com\.google\.firebase\.crashlytics') {
      $ok = $false
      $null = $details.Add('missing crashlytics gradle plugin')
    }
  }
  else {
    $ok = $false
    $null = $details.Add('missing android/app/build.gradle.kts')
  }

  $pubspec = Join-Path $dir 'pubspec.yaml'
  if (Test-Path $pubspec) {
    $pubText = Get-Content $pubspec -Raw
    if ($pubText -notmatch 'firebase_crashlytics') {
      $ok = $false
      $null = $details.Add('missing firebase_crashlytics dependency')
    }
    if ($pubText -notmatch 'firebase_analytics') {
      $ok = $false
      $null = $details.Add('missing firebase_analytics dependency')
    }
  }

  Add-Result -Name ("SDK files: {0}" -f $Config.Label) -Passed $ok -Detail ($details -join '; ')
}

function Invoke-ObservabilityPing {
  param([hashtable]$Config)

  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Add-Result -Name 'Observability ping' -Passed $false -Detail 'flutter not in PATH'
    return
  }

  $dir = $Config.Dir
  if (-not (Test-Path $dir)) {
    Add-Result -Name 'Observability ping' -Passed $false -Detail "missing dir $dir"
    return
  }

  $defines = @('PILOT_OBSERVABILITY_VERIFY=true')
  if ($ForceCrashlyticsTestCrash) {
    $defines += 'CRASHLYTICS_PILOT_CRASH=true'
  }

  $defineArgs = $defines | ForEach-Object { '--dart-define=' + $_ }

  Write-Step ("Sending observability ping on {0} (release build)" -f $Config.Label)
  if ($ForceCrashlyticsTestCrash -and -not $Quiet) {
    Write-Host 'WARNING: CRASHLYTICS_PILOT_CRASH=true — app will crash in ~5s' -ForegroundColor Yellow
  }

  Push-Location $dir
  try {
    & flutter run --release @defineArgs
    Add-Result -Name ("Observability ping: {0}" -f $Config.Label) -Passed ($LASTEXITCODE -eq 0) -Detail 'flutter run --release completed'
  }
  catch {
    Add-Result -Name ("Observability ping: {0}" -f $Config.Label) -Passed $false -Detail $_.Exception.Message
  }
  finally {
    Pop-Location
  }
}

Write-Step 'Van soft-launch pilot test'
Write-Host "Project: van-merchant | Primary app: $App" -ForegroundColor DarkGray

Write-Step '1) Tooling prerequisites'
Add-Result -Name 'Flutter CLI' -Passed ([bool](Get-Command flutter -ErrorAction SilentlyContinue))
Add-Result -Name 'Node.js' -Passed ([bool](Get-Command node -ErrorAction SilentlyContinue))
Add-Result -Name 'Firebase CLI' -Passed ([bool](Get-Command firebase -ErrorAction SilentlyContinue))

$javaMajor = Get-JavaMajorVersion
if ($SkipEmulator) {
  Add-Result -Name 'Java 21+ (emulator smoke)' -Passed $true -Detail "skipped; detected Java major=$javaMajor"
}
else {
  Add-Result -Name 'Java 21+ (emulator smoke)' -Passed ($javaMajor -ge 21) -Detail "detected Java major=$javaMajor"
}

Write-Step '2) Observability SDK files (van1–van4)'
foreach ($key in @('van1', 'van2', 'van3', 'van4')) {
  Test-AppObservabilityFiles -Config $AppMap[$key]
}

Write-Step '3) Firebase project apps (optional)'
if (Get-Command firebase -ErrorAction SilentlyContinue) {
  Push-Location $van2Root
  try {
    $appsJson = firebase apps:list ANDROID --project van-merchant --json 2>$null | Out-String
    $packages = @('van.merchant', 'Van2.com', 'van3.rider.com', 'van4.com')
    foreach ($pkg in $packages) {
      $found = $appsJson -match [regex]::Escape($pkg)
      Add-Result -Name ("Firebase Android app: $pkg") -Passed $found -Detail $(if ($found) { 'registered' } else { 'not found in apps:list' })
    }
  }
  catch {
    Add-Result -Name 'Firebase apps:list' -Passed $false -Detail 'run firebase login if needed' -Advisory:(-not $Strict)
  }
  finally {
    Pop-Location
  }
}
else {
  Add-Result -Name 'Firebase apps:list' -Passed $false -Detail 'firebase CLI missing'
}

if (-not $SkipEmulator) {
  Write-Step '4) Firestore rules + order lifecycle E2E'
  try {
    & (Join-Path $scriptRoot 'deploy-smoke-test.ps1') -AfterTarget firestore -Phase PreDeploy -Quiet:$Quiet
    Add-Result -Name 'Firestore smoke + E2E' -Passed ($LASTEXITCODE -eq 0)
  }
  catch {
    Add-Result -Name 'Firestore smoke + E2E' -Passed $false -Detail $_.Exception.Message
  }
}
else {
  Add-Result -Name 'Firestore smoke + E2E' -Passed $true -Detail 'skipped'
}

if (-not $SkipFlutterTests) {
  Write-Step '5) Flutter regression tests (van2)'
  Push-Location $van2Root
  try {
    $tests = @(
      'test/rider_unavailable_dialog_test.dart',
      'test/privacy_consent_service_test.dart',
      'test/help_pricing_summary_test.dart'
    )
    foreach ($testPath in $tests) {
      if (-not (Test-Path $testPath)) {
        Add-Result -Name ("Flutter test: $testPath") -Passed $false -Detail 'file missing'
        continue
      }
      & flutter test $testPath
      Add-Result -Name ("Flutter test: $testPath") -Passed ($LASTEXITCODE -eq 0)
    }
  }
  finally {
    Pop-Location
  }
}

if ($SendObservabilityPing) {
  Write-Step '6) Crashlytics / Analytics live ping'
  Invoke-ObservabilityPing -Config $AppMap[$App]
}

Write-Step 'Summary'
$failures = @($results | Where-Object { $_.Status -eq 'FAIL' })
$warnings = @($results | Where-Object { $_.Status -eq 'WARN' })
$results | Format-Table -AutoSize

if (-not $SendObservabilityPing -and -not $Quiet) {
  Write-Host "`nCrashlytics Console steps:" -ForegroundColor Yellow
  Write-Host '  1) https://console.firebase.google.com/project/van-merchant/crashlytics'
  Write-Host '  2) Enable Crashlytics if prompted'
  Write-Host '  3) Run release ping:'
  Write-Host "     .\soft-launch-pilot-test.ps1 -SendObservabilityPing -App $App"
  Write-Host '  4) Optional fatal test crash (once):'
  Write-Host "     .\soft-launch-pilot-test.ps1 -SendObservabilityPing -App $App -ForceCrashlyticsTestCrash"
  Write-Host '  Full guide: scripts\CRASHLYTICS_SETUP.md'
}

if ($warnings.Count -gt 0 -and -not $Quiet) {
  Write-Host ("`nWarnings ({0}) - review before soft launch" -f $warnings.Count) -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
  Write-Host ("`nPilot test FAILED ({0} checks)" -f $failures.Count) -ForegroundColor Red
  exit 1
}

Write-Host '`nPilot test PASSED — review Crashlytics Console within 10 minutes after -SendObservabilityPing' -ForegroundColor Green
exit 0
