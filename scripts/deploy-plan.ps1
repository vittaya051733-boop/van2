<#
.SYNOPSIS
  Deploy workflow: impact + readiness + optional dry-run + deploy + post checklist.

.EXAMPLE
  # ข้อ 5 — ดูแผน + dry-run ไม่ deploy จริง
  .\deploy-plan.ps1 -App van2 -Target firestore -DryRunOnly

  # deploy จริง (ข้อ 1,2,6 อัตโนมัติ + ข้อ 4 หลัง deploy)
  .\deploy-plan.ps1 -App van2 -Target firestore -Execute
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App,

  [Parameter(Mandatory)]
  [ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')]
  [string]$Target,

  [string[]]$FunctionName,

  [switch]$DryRunOnly,
  [switch]$Execute,
  [switch]$SkipPreDeploySmoke,
  [switch]$AllowSkipEmulatorSmoke,

  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge,
  [switch]$InteractiveConfirm,
  [switch]$BuildWeb
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')

if ([string]::IsNullOrWhiteSpace($FinalAcknowledge)) {
  $FinalAcknowledge = Get-VanAckTh
}

if (-not $DryRunOnly -and -not $Execute) {
  Write-Host ''
  Write-Host 'deploy-plan.ps1 — เลือกโหมด:' -ForegroundColor Cyan
  Write-Host '  -DryRunOnly   ข้อ 5: ตรวจ impact + readiness + dry-run (ไม่ deploy จริง)'
  Write-Host '  -Execute      deploy จริงผ่าน deploy-self.ps1 (backup อัตโนมัติถ้า firestore)'
  Write-Host ''
  Write-Host 'Example:'
  Write-Host '  .\deploy-plan.ps1 -App van2 -Target firestore -DryRunOnly'
  Write-Host '  .\deploy-plan.ps1 -App van2 -Target firestore -Execute'
  exit 0
}

Show-VanDeployImpactSummary -App $App -Target $Target

& (Join-Path $scriptRoot 'deploy-readiness.ps1') -App $App -Target $Target
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$selfScript = Join-Path $scriptRoot 'deploy-self.ps1'
$selfArgs = @{
  App                 = $App
  Target              = $Target
  FinalAcknowledge    = $FinalAcknowledge
  InteractiveConfirm  = $InteractiveConfirm
  BuildWeb            = $BuildWeb
  SkipReadiness       = $true
}

if ($ConfirmDeploy) { $selfArgs.ConfirmDeploy = $ConfirmDeploy }
if ($ConfirmFile) { $selfArgs.ConfirmFile = $ConfirmFile }
if ($ConfirmImpact) { $selfArgs.ConfirmImpact = $ConfirmImpact }
if ($FunctionName) { $selfArgs.FunctionName = $FunctionName }
if ($SkipPreDeploySmoke) { $selfArgs.SkipPreDeploySmoke = $true }
if ($AllowSkipEmulatorSmoke) { $selfArgs.AllowSkipEmulatorSmoke = $true }

if ($DryRunOnly) {
  Write-Host (Get-VanMsg 'planDryRun') -ForegroundColor Yellow
    if ($Target -eq 'firestore' -and $App -eq 'van2' -and -not $SkipPreDeploySmoke) {
    Write-Host (Get-VanMsg 'planPreDeployGate') -ForegroundColor Cyan
    $smokeScript = Join-Path $scriptRoot 'deploy-smoke-test.ps1'
    $smokeArgs = @{
      AfterTarget = 'firestore'
      Phase       = 'PreDeploy'
      SkipLive    = $true
    }
    if ($AllowSkipEmulatorSmoke) { $smokeArgs.AllowSkipEmulator = $true }
    & $smokeScript @smokeArgs
    if ($LASTEXITCODE -ne 0) {
      Write-Host (Get-VanMsg 'planPreDeployFail') -ForegroundColor Red
      exit $LASTEXITCODE
    }
  }
  & $selfScript @selfArgs -DryRun
  exit $LASTEXITCODE
}

Write-Host (Get-VanMsg 'planExecute') -ForegroundColor Cyan
& $selfScript @selfArgs
exit $LASTEXITCODE
