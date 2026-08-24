<#
.SYNOPSIS
  Deploy หลายเป้าหมายใน session เดียว — สำรองทุก step ก่อน deploy ใดๆ

.DESCRIPTION
  ใช้เมื่อต้อง deploy หลายแอป/หลาย target พร้อมกัน (เช่น van2:firestore + van4:firestore-van4)
  Phase 1: สำรอง artifact ทุก step ลง deploy-backups/sessions/{id}/
  Phase 2: deploy ทีละ step ผ่าน deploy-self.ps1

.EXAMPLE
  .\deploy-batch.ps1 -Step van2:firestore,van4:firestore-van4 -DryRunOnly

.EXAMPLE
  .\deploy-batch.ps1 -Step van2:firestore,van4:storage -Execute `
    -ConfirmDeploy "อนุมัติ:van2:van-merchant" `
    -FinalAcknowledge "ฉันเข้าใจแล้ว"
#>
param(
  [Parameter(Mandatory)]
  [string[]]$Step,

  [switch]$DryRunOnly,
  [switch]$Execute,

  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge,
  [switch]$InteractiveConfirm,
  [switch]$BuildWeb,
  [switch]$SkipPreDeploySmoke,
  [switch]$AllowSkipEmulatorSmoke
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')

if ([string]::IsNullOrWhiteSpace($FinalAcknowledge)) {
  $FinalAcknowledge = Get-VanAckTh
}

if (-not $DryRunOnly -and -not $Execute) {
  Write-Host ''
  Write-Host 'deploy-batch.ps1 — เลือกโหมด:' -ForegroundColor Cyan
  Write-Host '  -DryRunOnly   สำรอง + dry-run deploy ทุก step (ไม่ deploy จริง)'
  Write-Host '  -Execute      สำรองทั้งหมดก่อน แล้ว deploy ทีละ step'
  Write-Host ''
  Write-Host 'รูปแบบ step:'
  Write-Host '  van2:firestore'
  Write-Host '  van4:firestore-van4'
  Write-Host '  van1:storage'
  Write-Host '  van2:functions:pushAppNotification,recordCheckoutDiscounts'
  Write-Host ''
  Write-Host 'Example:'
  Write-Host '  .\deploy-batch.ps1 -Step van2:firestore,van4:firestore-van4 -DryRunOnly'
  exit 0
}

$parsedSteps = @()
foreach ($raw in $Step) {
  foreach ($part in ($raw -split ',')) {
    $token = $part.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) { continue }
    $parsed = Parse-VanDeployBatchStep -Step $token
    $parsedSteps += $parsed
  }
}

if ($parsedSteps.Count -eq 0) {
  throw 'No valid steps provided.'
}

Write-Host ''
Write-Host (Get-VanMsg 'batchTitle') -ForegroundColor Cyan
foreach ($s in $parsedSteps) {
  $label = "$($s.App)/$($s.Target)"
  if ($s.FunctionName.Count -gt 0) {
    $label += " ($($s.FunctionName -join ','))"
  }
  Write-Host "  - $label"
}
Write-Host ''

foreach ($s in $parsedSteps) {
  Show-VanDeployImpactSummary -App $s.App -Target $s.Target
  & (Join-Path $scriptRoot 'deploy-readiness.ps1') -App $s.App -Target $s.Target -Quiet
  if ($LASTEXITCODE -ne 0) {
    throw (Get-VanMsg 'batchReadinessFailed' @("$($s.App)/$($s.Target)"))
  }
}

$session = Initialize-VanDeployBatchSession -DryRun:$DryRunOnly
$backups = Backup-VanDeployBatchSteps -Steps $parsedSteps -DryRun:$DryRunOnly

$selfScript = Join-Path $scriptRoot 'deploy-self.ps1'
$stepIndex = 0
foreach ($s in $parsedSteps) {
  $stepIndex++
  $backup = $backups[$stepIndex - 1]
  $env:VAN_LAST_DEPLOY_BACKUP_DIR = $backup.backupDir
  $env:VAN_PREDEPLOY_BACKUP_DONE = "$($s.App):$($s.Target)"

  Write-Host ''
  Write-Host (Get-VanMsg 'batchDeployStep' @($stepIndex, $parsedSteps.Count, "$($s.App)/$($s.Target)")) -ForegroundColor Cyan

  $selfArgs = @{
    App                   = $s.App
    Target                = $s.Target
    FinalAcknowledge      = $FinalAcknowledge
    InteractiveConfirm    = $InteractiveConfirm
    BuildWeb              = $BuildWeb
    SkipReadiness         = $true
    SkipPreDeployBackup   = $true
  }

  if ($ConfirmDeploy) { $selfArgs.ConfirmDeploy = $ConfirmDeploy }
  if ($ConfirmFile) { $selfArgs.ConfirmFile = $ConfirmFile }
  if ($ConfirmImpact) { $selfArgs.ConfirmImpact = $ConfirmImpact }
  if ($s.FunctionName.Count -gt 0) { $selfArgs.FunctionName = $s.FunctionName }
  if ($SkipPreDeploySmoke) { $selfArgs.SkipPreDeploySmoke = $true }
  if ($AllowSkipEmulatorSmoke) { $selfArgs.AllowSkipEmulatorSmoke = $true }
  if ($DryRunOnly) { $selfArgs.DryRun = $true }

  & $selfScript @selfArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Host (Get-VanMsg 'batchStepFailed' @($stepIndex, $session.sessionId)) -ForegroundColor Red
    Write-Host (Get-VanMsg 'batchRollbackHint' @($session.sessionDir)) -ForegroundColor Yellow
    exit $LASTEXITCODE
  }
}

Write-Host ''
Write-Host (Get-VanMsg 'batchComplete' @($session.sessionId, $session.sessionDir)) -ForegroundColor Green
exit 0
