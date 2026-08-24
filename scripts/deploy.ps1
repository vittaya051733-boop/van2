<#
.SYNOPSIS
  จุดเข้า deploy เดียวของ ecosystem van-merchant (เฟส 2)

.DESCRIPTION
  ทางแนะนำ:
    .\deploy.ps1 -Bundle BUNDLE-A01 -ShowOnly
    .\deploy.ps1 -Bundle BUNDLE-S01 -Execute ...
    .\deploy.ps1 -App van3 -Target storage ...
    .\deploy.ps1 -Health
    .\deploy.ps1 -Ledger

  ห้าม: firebase deploy ดิบ

.EXAMPLE
  .\deploy.ps1 -List
  .\deploy.ps1 -Health -MatrixOnly
  .\deploy.ps1 -Bundle BUNDLE-ST3 -DryRunOnly
#>
param(
  [string]$Bundle,
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App,
  [ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')]
  [string]$Target,
  [string[]]$FunctionName,

  [switch]$List,
  [switch]$ShowOnly,
  [switch]$DryRunOnly,
  [switch]$Execute,
  [switch]$Health,
  [switch]$MatrixOnly,
  [switch]$Ledger,
  [int]$LedgerLast = 30,

  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge,
  [switch]$InteractiveConfirm,
  [switch]$BuildWeb,
  [switch]$SkipPreDeploySmoke,
  [switch]$AllowSkipEmulatorSmoke,
  [switch]$SkipLive,
  [switch]$SkipEmulator
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')
. (Join-Path $scriptRoot 'deploy-backup.ps1')
. (Join-Path $scriptRoot 'deploy-ledger.ps1')

Write-Host ''
Write-Host '=== van-merchant deploy entry (ใช้สคริปต์นี้เท่านั้น) ===' -ForegroundColor Cyan
Write-Host 'ห้าม: firebase deploy / firebase deploy --only ...' -ForegroundColor Red
Write-Host ''

if ($Ledger) {
  Show-VanDeployLedger -Last $LedgerLast
  exit 0
}

if ($Health -or $MatrixOnly) {
  $healthArgs = @{}
  if ($MatrixOnly) { $healthArgs.MatrixOnly = $true }
  if ($App) { $healthArgs.App = $App }
  if ($SkipLive) { $healthArgs.SkipLive = $true }
  if ($SkipEmulator) { $healthArgs.SkipEmulator = $true }
  if ($AllowSkipEmulatorSmoke) { $healthArgs.AllowSkipEmulator = $true }
  & (Join-Path $scriptRoot 'ecosystem-health.ps1') @healthArgs
  exit $LASTEXITCODE
}

if ($List -or (-not $Bundle -and -not $App)) {
  & (Join-Path $scriptRoot 'deploy-bundle.ps1') -List
  Write-Host 'หรือ: deploy.ps1 -App vanN -Target storage|hosting|functions|firestore|firestore-van4' -ForegroundColor Green
  Write-Host 'หรือ: deploy.ps1 -Health | deploy.ps1 -Health -MatrixOnly | deploy.ps1 -Ledger' -ForegroundColor Green
  Write-Host ''
  exit 0
}

if ($Bundle) {
  $bundleArgs = @{ Bundle = $Bundle }
  if ($ShowOnly) { $bundleArgs.ShowOnly = $true }
  if ($DryRunOnly) { $bundleArgs.DryRunOnly = $true }
  if ($Execute) { $bundleArgs.Execute = $true }
  if ($ConfirmDeploy) { $bundleArgs.ConfirmDeploy = $ConfirmDeploy }
  if ($ConfirmImpact) { $bundleArgs.ConfirmImpact = $ConfirmImpact }
  if ($FinalAcknowledge) { $bundleArgs.FinalAcknowledge = $FinalAcknowledge }
  if ($InteractiveConfirm) { $bundleArgs.InteractiveConfirm = $true }
  if ($BuildWeb) { $bundleArgs.BuildWeb = $true }
  if ($SkipPreDeploySmoke) { $bundleArgs.SkipPreDeploySmoke = $true }
  if ($AllowSkipEmulatorSmoke) { $bundleArgs.AllowSkipEmulatorSmoke = $true }

  if (-not $ShowOnly -and -not $DryRunOnly -and -not $Execute) {
    $bundleArgs.ShowOnly = $true
  }

  & (Join-Path $scriptRoot 'deploy-bundle.ps1') @bundleArgs
  $code = $LASTEXITCODE
  $status = if ($code -eq 0) { 'ok' } else { 'fail' }
  $kind = if ($Execute) { 'bundle-execute' } elseif ($DryRunOnly) { 'bundle-dryrun' } else { 'bundle-show' }
  Write-VanDeployLedgerEntry -Kind $kind -Bundle $Bundle -Status $status
  exit $code
}

if ($App -and $Target) {
  $selfArgs = @{
    App    = $App
    Target = $Target
  }
  if ($FunctionName) { $selfArgs.FunctionName = $FunctionName }
  if ($ConfirmDeploy) { $selfArgs.ConfirmDeploy = $ConfirmDeploy }
  if ($ConfirmFile) { $selfArgs.ConfirmFile = $ConfirmFile }
  if ($ConfirmImpact) { $selfArgs.ConfirmImpact = $ConfirmImpact }
  if ($FinalAcknowledge) { $selfArgs.FinalAcknowledge = $FinalAcknowledge }
  if ($InteractiveConfirm) { $selfArgs.InteractiveConfirm = $true }
  if ($BuildWeb) { $selfArgs.BuildWeb = $true }
  if ($DryRunOnly) { $selfArgs.DryRun = $true }
  if ($SkipPreDeploySmoke) { $selfArgs.SkipPreDeploySmoke = $true }
  if ($AllowSkipEmulatorSmoke) { $selfArgs.AllowSkipEmulatorSmoke = $true }

  & (Join-Path $scriptRoot 'deploy-self.ps1') @selfArgs
  $code = $LASTEXITCODE
  $status = if ($code -eq 0) { 'ok' } else { 'fail' }
  $kind = if ($DryRunOnly) { 'self-dryrun' } else { 'self-execute' }
  Write-VanDeployLedgerEntry -Kind $kind -App $App -Target $Target -Status $status
  exit $code
}

Write-Host 'ระบุ -Bundle หรือ -App/-Target หรือ -Health / -Ledger' -ForegroundColor Yellow
exit 1
