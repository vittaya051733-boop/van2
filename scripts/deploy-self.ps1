<#
.SYNOPSIS
  Single entry point — deploy ONE target for ONE app (never combined).

.DESCRIPTION
  Routes to deploy-safe.ps1 / per-app isolated scripts.
  AI agents and humans MUST use this instead of raw firebase deploy.

  Workflow แนะนำ: deploy-plan.ps1 -DryRunOnly แล้วค่อย -Execute

.EXAMPLE
  .\deploy-self.ps1 -App van3 -Target storage -ConfirmDeploy "APPROVE:van3:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App,

  [Parameter(Mandatory)]
  [ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')]
  [string]$Target,

  [string[]]$FunctionName,

  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge = 'YES I UNDERSTAND',
  [switch]$InteractiveConfirm,
  [switch]$DryRun,
  [switch]$BuildWeb,
  [switch]$SkipReadiness,
  [switch]$SkipPostGuide,
  [switch]$SkipPreDeploySmoke,
  [switch]$AllowSkipEmulatorSmoke
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')

$cfg = Get-VanGovernanceConfig
$safeScript = Join-Path $scriptRoot 'deploy-safe.ps1'
$readinessScript = Join-Path $scriptRoot 'deploy-readiness.ps1'

if (-not $SkipReadiness) {
  Show-VanDeployImpactSummary -App $App -Target $Target
  & $readinessScript -App $App -Target $Target -Quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Readiness check failed. Fix issues or use -SkipReadiness (not recommended)."
  }
}

$script:VanLastFirestoreBackupPath = $null

function Invoke-VanFirestoreSmokeGate {
  param(
    [Parameter(Mandatory)][ValidateSet('PreDeploy', 'PostDeploy')][string]$Phase
  )

  $smokeScript = Join-Path $scriptRoot 'deploy-smoke-test.ps1'
  if (-not (Test-Path $smokeScript)) {
    throw "Missing smoke test script: $smokeScript"
  }

  $smokeArgs = @{
    AfterTarget = 'firestore'
    Phase       = $Phase
    SkipLive    = $true
  }
  if ($AllowSkipEmulatorSmoke) {
    $smokeArgs.AllowSkipEmulator = $true
  }
  if ($Phase -eq 'PostDeploy') {
    $smokeArgs.Remove('SkipLive')
  }

  if ($Phase -eq 'PreDeploy') {
    Write-Host ''
    Write-Host '=== Pre-Deploy Firestore Gate ===' -ForegroundColor Cyan
  }

  & $smokeScript @smokeArgs
  if ($LASTEXITCODE -ne 0) {
    if ($Phase -eq 'PreDeploy') {
      throw 'Pre-deploy smoke gate failed — Firestore deploy blocked. Fix rules/emulator (Java 21+) first.'
    }
    return $false
  }
  return $true
}

function Invoke-VanDeploySelfTarget {
  param(
    [string[]]$ExtraArgs = @()
  )

  switch ($Target) {
    'storage' {
      & $safeScript -Action storage -App $App `
        -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App $App }) `
        -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { 'storage.rules' }) `
        -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { "SELF:$App" }) `
        -FinalAcknowledge $FinalAcknowledge `
        -InteractiveConfirm:$InteractiveConfirm `
        -DryRun:$DryRun @ExtraArgs
    }
    'firestore' {
      if ($App -ne 'van2') {
        throw "Firestore (default DB) deploy is van2 only. Current: $App. See DEPLOY_RISK_MATRIX.md"
      }
      $firestoreScript = Join-Path $scriptRoot 'deploy-firestore-isolated.ps1'
      & $firestoreScript `
        -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App 'van2' }) `
        -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { $cfg.FirestoreCanonicalFile }) `
        -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { $cfg.FirestoreSharedImpact }) `
        -FinalAcknowledge $FinalAcknowledge `
        -InteractiveConfirm:$InteractiveConfirm `
        -DryRun:$DryRun
      $script:VanLastFirestoreBackupPath = $env:VAN_LAST_FIRESTORE_BACKUP
      $env:VAN_LAST_FIRESTORE_BACKUP = $null
    }
    'firestore-van4' {
      & $safeScript -Action firestore-van4 -App van4 `
        -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App 'van4' }) `
        -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { 'firestore.rules' }) `
        -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { 'SELF:van4' }) `
        -FinalAcknowledge $FinalAcknowledge `
        -InteractiveConfirm:$InteractiveConfirm `
        -DryRun:$DryRun @ExtraArgs
    }
    'functions' {
      if ($App -notin @('van1', 'van2')) {
        throw "$App has no Cloud Functions. Functions deploy: van1 or van2 only."
      }
      if (-not $FunctionName -or $FunctionName.Count -eq 0) {
        throw 'Provide -FunctionName <name> (one function at a time recommended).'
      }
      & $safeScript -Action functions -App $App -FunctionName $FunctionName `
        -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App $App }) `
        -FinalAcknowledge $FinalAcknowledge `
        -InteractiveConfirm:$InteractiveConfirm `
        -DryRun:$DryRun @ExtraArgs
    }
    'hosting' {
      Assert-VanAppCanDeploy -App $App -Target 'hosting'
      $appCfg = $cfg.Apps[$App]
      $isolatedScript = Join-Path $appCfg.Root 'scripts\deploy-isolated.ps1'
      if (-not (Test-Path $isolatedScript)) {
        throw "Missing deploy-isolated.ps1 for $App"
      }

      $hostArgs = @{
        ConfirmDeploy       = $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App $App })
        ConfirmFile         = $(if ($ConfirmFile) { $ConfirmFile } else { 'firebase.json' })
        ConfirmImpact       = $(if ($ConfirmImpact) { $ConfirmImpact } else { "SELF:$App" })
        FinalAcknowledge    = $FinalAcknowledge
        InteractiveConfirm  = $InteractiveConfirm
        DryRun              = $DryRun
      }

      switch ($App) {
        'van1' { & $isolatedScript @hostArgs -HostingOnly -BuildWeb:$BuildWeb }
        'van2' { & $isolatedScript @hostArgs -HostingOnly -BuildWeb:$BuildWeb }
        'van3' { & $isolatedScript @hostArgs -DeployHosting -BuildWeb:$BuildWeb }
        'van4' { & $isolatedScript @hostArgs -DeployHosting -BuildWeb:$BuildWeb }
      }
    }
  }
}

if ($Target -eq 'firestore' -and $App -eq 'van2' -and -not $SkipPreDeploySmoke -and -not $DryRun) {
  Invoke-VanFirestoreSmokeGate -Phase PreDeploy
}

Invoke-VanDeploySelfTarget
$exitCode = $LASTEXITCODE

if (-not $SkipPostGuide -and -not $DryRun -and $exitCode -eq 0) {
  $needsSmoke = $Target -in @('firestore', 'functions', 'firestore-van4')
  if ($needsSmoke) {
    if ($Target -eq 'firestore') {
      $postOk = Invoke-VanFirestoreSmokeGate -Phase PostDeploy
      if (-not $postOk) {
        Write-Host 'WARNING: Post-deploy emulator smoke failed. Consider rollback (see DEPLOY_CONNECTION_SIGNALS.md).' -ForegroundColor Red
        Show-VanPostDeployConnectionGuide -App $App -Target $Target -BackupPath $script:VanLastFirestoreBackupPath
        exit 1
      }
    }
    else {
      $smokeScript = Join-Path $scriptRoot 'deploy-smoke-test.ps1'
      if (Test-Path $smokeScript) {
        & $smokeScript -AfterTarget $Target -Phase PostDeploy
        if ($LASTEXITCODE -ne 0) {
          Write-Host 'WARNING: Smoke test failed after deploy. Consider rollback.' -ForegroundColor Red
          exit $LASTEXITCODE
        }
      }
    }
  }
  Show-VanPostDeployConnectionGuide -App $App -Target $Target -BackupPath $script:VanLastFirestoreBackupPath
}

exit $exitCode
