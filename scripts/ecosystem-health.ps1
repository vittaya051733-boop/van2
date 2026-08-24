<#
.SYNOPSIS
  Ecosystem Health Checklist — run once, report which van/collection may be down.

.EXAMPLE
  .\ecosystem-health.ps1 -MatrixOnly
  .\ecosystem-health.ps1
  .\ecosystem-health.ps1 -App van3
#>
param(
  [ValidateSet('all', 'van1', 'van2', 'van3', 'van4')]
  [string]$App = 'all',

  [switch]$MatrixOnly,
  [switch]$SkipEmulator,
  [switch]$AllowSkipEmulator,
  [switch]$SkipLive,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')

$checklistPath = Join-Path $scriptRoot 'ECOSYSTEM_HEALTH_CHECKLIST.json'
if (-not (Test-Path $checklistPath)) {
  throw "Missing checklist: $checklistPath"
}

$checklist = Get-Content $checklistPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reportDir = Join-Path $scriptRoot 'deploy-backups\health-reports'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $reportDir "health-$stamp.json"

function Write-HealthTitle {
  param([string]$Text, [string]$Color = 'Cyan')
  if (-not $Quiet) {
    Write-Host ''
    Write-Host $Text -ForegroundColor $Color
  }
}

function Show-HealthMatrix {
  Write-HealthTitle (Get-VanMsg 'healthTitle')
  if (-not $Quiet) {
    Write-Host (Get-VanMsg 'healthUpdated' @($checklist.updated)) -ForegroundColor Gray
    Write-Host (Get-VanMsg 'healthHowTo' @($checklist.howToRun)) -ForegroundColor Gray
  }

  foreach ($layer in @($checklist.layers)) {
    if ($App -ne 'all' -and $layer.app -and $layer.app -ne $App) {
      continue
    }
    Write-HealthTitle ("--- {0} ---" -f $layer.titleTh) 'Yellow'
    foreach ($p in @($layer.points)) {
      if ($App -ne 'all') {
        $apps = @()
        if ($p.van) { $apps += @($p.van) }
        if ($p.apps) { $apps += @($p.apps) }
        if ($layer.app) { $apps += $layer.app }
        if ($apps.Count -gt 0 -and ($apps -notcontains $App)) { continue }
      }

      $id = $p.id
      $col = if ($p.collection) { $p.collection } elseif ($p.resource) { $p.resource } else { $p.titleTh }
      $screen = if ($p.screenTh) { $p.screenTh } elseif ($p.symptomTh) { $p.symptomTh } else { $p.titleTh }
      $prio = if ($p.priority) { "P$($p.priority)" } else { '  ' }
      $auto = $p.auto
      if (-not $Quiet) {
        Write-Host ("  [{0}] {1,-14}  {2,-42}  {3}" -f $prio, $id, $col, $screen) -ForegroundColor White
        Write-Host ("         auto={0}" -f $auto) -ForegroundColor DarkGray
      }
    }
  }

  Write-HealthTitle (Get-VanMsg 'healthSymptomTitle') 'DarkYellow'
  if (-not $Quiet) {
    $map = $checklist.symptomMapTh
    Write-Host ("  permission-denied -> {0}" -f $map.'permission-denied')
    Write-Host ("  spinner            -> {0}" -f $map.spinner)
    Write-Host ("  stale-data         -> {0}" -f $map.'stale-data')
    Write-Host ("  no-push            -> {0}" -f $map.'no-push')
  }
}

function Get-ManualChecklistForApp {
  param([string]$Van)

  $items = @()
  foreach ($layer in @($checklist.layers)) {
    if ($layer.app -and $layer.app -ne $Van) { continue }
    foreach ($p in @($layer.points)) {
      $apps = @()
      if ($p.van) { $apps += @($p.van) }
      if ($p.apps) { $apps += @($p.apps) }
      if ($layer.app) { $apps += $layer.app }
      if ($apps -notcontains $Van -and $layer.app -ne $Van) { continue }
      if ($p.priority -and [int]$p.priority -gt 2) { continue }

      $items += [ordered]@{
        id         = $p.id
        collection = $(if ($p.collection) { $p.collection } else { $p.resource })
        screenTh   = $(if ($p.screenTh) { $p.screenTh } elseif ($p.titleTh) { $p.titleTh } else { $p.symptomTh })
        auto       = $p.auto
        status     = 'MANUAL'
      }
    }
  }
  return $items
}

function Show-ManualSmokeHints {
  Write-HealthTitle (Get-VanMsg 'healthManualTitle') 'Yellow'
  $order = @('van3', 'van2', 'van1', 'van4')
  if ($App -ne 'all') { $order = @($App) }

  foreach ($van in $order) {
    Write-Host ''
    Write-Host ("  [{0}]" -f $van) -ForegroundColor Cyan
    foreach ($item in (Get-ManualChecklistForApp -Van $van)) {
      Write-Host ("    [ ] {0} | {1} | {2}" -f $item.id, $item.collection, $item.screenTh)
    }
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'healthManualOrder') -ForegroundColor DarkYellow
}

Show-HealthMatrix

if ($MatrixOnly) {
  Show-ManualSmokeHints
  Write-HealthTitle (Get-VanMsg 'healthMatrixOnly') 'DarkYellow'
  Write-Host (Get-VanMsg 'healthRunFull') -ForegroundColor Green
  exit 0
}

$results = [ordered]@{
  timestamp = $stamp
  project   = $checklist.project
  appFilter = $App
  steps     = @()
}

Write-HealthTitle (Get-VanMsg 'healthStep1') 'Cyan'
$readinessScript = Join-Path $scriptRoot 'deploy-readiness.ps1'
$appsToCheck = if ($App -eq 'all') { @('van1', 'van2', 'van3', 'van4') } else { @($App) }
$targetByApp = @{
  van1 = 'storage'
  van2 = 'firestore'
  van3 = 'storage'
  van4 = 'storage'
}

foreach ($a in $appsToCheck) {
  $t = $targetByApp[$a]
  Write-Host (Get-VanMsg 'healthReadyRun' @($a, $t)) -ForegroundColor DarkGray
  & $readinessScript -App $a -Target $t -Quiet
  $ok = ($LASTEXITCODE -eq 0)
  $results.steps += [ordered]@{
    id     = "ready-$a"
    van    = $a
    target = $t
    status = $(if ($ok) { 'PASS' } else { 'FAIL' })
  }
  if ($ok) {
    Write-Host (Get-VanMsg 'healthReadyPass' @($a)) -ForegroundColor Green
  }
  else {
    Write-Host (Get-VanMsg 'healthReadyFail' @($a)) -ForegroundColor Red
  }
}

Write-HealthTitle (Get-VanMsg 'healthStep2') 'Cyan'
$smokeScript = Join-Path $scriptRoot 'deploy-smoke-test.ps1'
$smokeArgs = @{
  AfterTarget = 'firestore'
  Phase       = 'PostDeploy'
  Quiet       = $Quiet
}
if ($SkipLive) { $smokeArgs.SkipLive = $true }
if ($SkipEmulator) { $smokeArgs.SkipEmulator = $true }
if ($AllowSkipEmulator) { $smokeArgs.AllowSkipEmulator = $true }

& $smokeScript @smokeArgs
$smokeOk = ($LASTEXITCODE -eq 0)
$results.steps += [ordered]@{
  id     = 'smoke-firestore'
  van    = 'all'
  target = 'firestore'
  status = $(if ($smokeOk) { 'PASS' } else { 'FAIL' })
  noteTh = $(if ($smokeOk) {
      (Get-VanMsg 'healthSmokeOkNote')
    } else {
      (Get-VanMsg 'healthSmokeFailNote')
    })
}

if ($smokeOk) {
  Write-Host (Get-VanMsg 'healthSmokePass') -ForegroundColor Green
}
else {
  Write-Host (Get-VanMsg 'healthSmokeFail') -ForegroundColor Red
}

Write-HealthTitle (Get-VanMsg 'healthSummaryTitle') 'Cyan'
$failCount = @($results.steps | Where-Object { $_.status -eq 'FAIL' }).Count
$passCount = @($results.steps | Where-Object { $_.status -eq 'PASS' }).Count

Write-Host (Get-VanMsg 'healthPassFail' @($passCount, $failCount)) -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ''

if ($failCount -gt 0) {
  Write-Host (Get-VanMsg 'healthSuspectTitle') -ForegroundColor Red
  Write-Host (Get-VanMsg 'healthSuspect1')
  Write-Host (Get-VanMsg 'healthSuspect2')
  Write-Host (Get-VanMsg 'healthSuspect3')
  Write-Host ''
  Write-Host (Get-VanMsg 'healthRollbackTitle') -ForegroundColor Yellow
  Write-Host (Get-VanMsg 'healthRollback1')
  Write-Host (Get-VanMsg 'healthRollback2')
}
else {
  Write-Host (Get-VanMsg 'healthAllPass') -ForegroundColor Green
}

Show-ManualSmokeHints

# Per-point status map (Phase 3)
$pointStatuses = @()
foreach ($layer in @($checklist.layers)) {
  if ($App -ne 'all' -and $layer.app -and $layer.app -ne $App) { continue }
  foreach ($p in @($layer.points)) {
    $status = 'MANUAL'
    $note = ''
    if ($p.auto -match 'compile|emulator') {
      if ($smokeOk) {
        $status = 'PASS'
        $note = 'covered by firestore smoke'
      }
      else {
        $status = 'FAIL'
        $note = 'smoke failed - suspect this point if van uses it'
      }
    }
    elseif ($p.auto -eq 'manual') {
      $status = 'MANUAL'
      $note = 'requires hand test'
    }
    $pointStatuses += [ordered]@{
      id         = $p.id
      van        = $(if ($layer.app) { $layer.app } else { 'shared' })
      collection = $(if ($p.collection) { $p.collection } elseif ($p.resource) { $p.resource } else { $p.titleTh })
      auto       = $p.auto
      priority   = $p.priority
      status     = $status
      note       = $note
    }
  }
}

Write-HealthTitle (Get-VanMsg 'healthPerPointTitle') 'Cyan'
$failPoints = @($pointStatuses | Where-Object { $_.status -eq 'FAIL' })
$passPoints = @($pointStatuses | Where-Object { $_.status -eq 'PASS' })
$manualPoints = @($pointStatuses | Where-Object { $_.status -eq 'MANUAL' })
Write-Host (Get-VanMsg 'healthPerPointCounts' @($passPoints.Count, $failPoints.Count, $manualPoints.Count))
if ($failPoints.Count -gt 0) {
  Write-Host (Get-VanMsg 'healthPerPointFailHeader') -ForegroundColor Red
  foreach ($fp in $failPoints) {
    if ($fp.priority -and [int]$fp.priority -gt 2) { continue }
    Write-Host ("    FAIL {0} | {1} | {2}" -f $fp.id, $fp.van, $fp.collection)
  }
}

$results.points = $pointStatuses
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$results | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host (Get-VanMsg 'healthReportSaved' @($reportPath)) -ForegroundColor Gray
if (Get-Command Write-VanDeployLedgerEntry -ErrorAction SilentlyContinue) {
  Write-VanDeployLedgerEntry -Kind 'health' -App $App -Status $(if ($failCount -gt 0) { 'fail' } else { 'ok' }) -Extra @{
    report = $reportPath
    passPoints = $passPoints.Count
    failPoints = $failPoints.Count
    manualPoints = $manualPoints.Count
  }
}
Write-Host ''

if ($failCount -gt 0) {
  exit 1
}
exit 0
