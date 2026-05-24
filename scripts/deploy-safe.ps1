param(
  [Parameter(Mandatory)]
  [ValidateSet('help', 'preflight', 'sync-rules', 'firestore', 'functions', 'storage', 'firestore-van4')]
  [string]$Action,

  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App = 'van2',

  [string[]]$FunctionName,

  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge = 'YES I UNDERSTAND',
  [switch]$InteractiveConfirm,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')

$cfg = Get-VanGovernanceConfig
$paths = Get-VanGovernanceRoot

switch ($Action) {
  'help' {
    Show-VanDeployGovernanceHelp
    exit 0
  }

  'preflight' {
    $target = switch ($App) {
      'van2' { 'firestore' }
      'van4' { 'storage' }
      default { 'storage' }
    }
    Invoke-VanDeployPreflight -App $App -Target $target
    Write-Host "[safe] Preflight OK for $App / $target" -ForegroundColor Green
    exit 0
  }

  'sync-rules' {
    if ($DryRun) {
      Sync-VanFirestoreRules -WhatIf
    } else {
      Sync-VanFirestoreRules
    }
    exit 0
  }

  'firestore' {
    if ($App -ne 'van2') {
      throw "Firestore deploy must run from van2 (canonical). Use: deploy-safe.ps1 -Action firestore -App van2"
    }

    Invoke-VanDeployPreflight -App 'van2' -Target 'firestore'
    Sync-VanFirestoreRules

    $firestoreScript = Join-Path $scriptRoot 'deploy-firestore-isolated.ps1'
    & $firestoreScript `
      -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App 'van2' }) `
      -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { $cfg.FirestoreCanonicalFile }) `
      -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { $cfg.FirestoreSharedImpact }) `
      -FinalAcknowledge $FinalAcknowledge `
      -InteractiveConfirm:$InteractiveConfirm `
      -DryRun:$DryRun
    exit $LASTEXITCODE
  }

  'functions' {
    if ($App -notin @('van1', 'van2')) {
      throw 'Functions deploy only allowed for van1 or van2.'
    }
    if (-not $FunctionName -or $FunctionName.Count -eq 0) {
      throw 'Provide -FunctionName <name> (one or more explicit function names).'
    }

    Invoke-VanDeployPreflight -App $App -Target 'functions'
    Assert-VanFunctionOwnership -App $App -FunctionName $FunctionName

    $fnScript = Join-Path $cfg.Apps[$App].Root 'scripts\deploy-functions-isolated.ps1'
    if (-not (Test-Path $fnScript)) {
      throw "Missing deploy-functions-isolated.ps1 for $App : $fnScript"
    }

    & $fnScript `
      -FunctionName $FunctionName `
      -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App $App }) `
      -ConfirmFile 'functions' `
      -ConfirmImpact "SELF:$App" `
      -FinalAcknowledge $FinalAcknowledge `
      -InteractiveConfirm:$InteractiveConfirm `
      -DryRun:$DryRun
    exit $LASTEXITCODE
  }

  'storage' {
    if ($App -notin @('van1', 'van2', 'van3', 'van4')) {
      throw 'Invalid app for storage deploy.'
    }
    $storageScript = Join-Path $cfg.Apps[$App].Root 'scripts\deploy-storage-isolated.ps1'
    & $storageScript `
      -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App $App }) `
      -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { 'storage.rules' }) `
      -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { "SELF:$App" }) `
      -FinalAcknowledge $FinalAcknowledge `
      -InteractiveConfirm:$InteractiveConfirm `
      -DryRun:$DryRun
    exit $LASTEXITCODE
  }

  'firestore-van4' {
    if ($App -ne 'van4') {
      throw 'Isolated Firestore DB deploy is van4 only. Use -App van4'
    }
    $fsScript = Join-Path $cfg.Apps.van4.Root 'scripts\deploy-firestore-isolated.ps1'
    & $fsScript `
      -ConfirmDeploy $(if ($ConfirmDeploy) { $ConfirmDeploy } else { Get-VanDeployConfirmToken -App 'van4' }) `
      -ConfirmFile $(if ($ConfirmFile) { $ConfirmFile } else { 'firestore.rules' }) `
      -ConfirmImpact $(if ($ConfirmImpact) { $ConfirmImpact } else { 'SELF:van4' }) `
      -FinalAcknowledge $FinalAcknowledge `
      -InteractiveConfirm:$InteractiveConfirm `
      -DryRun:$DryRun
    exit $LASTEXITCODE
  }
}
