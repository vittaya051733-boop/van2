param(
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun,
  [string]$DatabaseId = '(default)'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'deploy-governance.ps1')

$cfg = Get-VanGovernanceConfig
$paths = Get-VanGovernanceRoot
$appRoot = $paths.Van2Root
Set-Location $appRoot

if ([string]::IsNullOrWhiteSpace($FinalAcknowledge)) {
  $FinalAcknowledge = Get-VanAckTh
}

$rulesFile = $cfg.FirestoreCanonicalFile

Assert-VanDeployConfirmation -App 'van2' -ConfirmDeploy $ConfirmDeploy
Assert-VanFileConfirmation -ConfirmFile $ConfirmFile -ExpectedFile $rulesFile
Assert-VanImpactConfirmation -ConfirmImpact $ConfirmImpact -ExpectedImpact $cfg.FirestoreSharedImpact
Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge

if ($InteractiveConfirm) {
  $expectedImpactTh = ConvertTo-VanImpactTokenTh $cfg.FirestoreSharedImpact
  $interactiveFile = Read-Host (Get-VanMsg 'interactiveFilePrompt' @($rulesFile))
  if ($interactiveFile -ne $rulesFile) {
    Write-Error (Get-VanMsg 'interactiveFileFail')
    exit 1
  }
  $interactiveImpact = Read-Host (Get-VanMsg 'interactiveImpactPrompt' @($expectedImpactTh))
  if (-not (Test-VanImpactTokenMatch -Provided $interactiveImpact -ExpectedEn $cfg.FirestoreSharedImpact)) {
    Write-Error (Get-VanMsg 'interactiveImpactFail')
    exit 1
  }
  Write-Host (Get-VanMsg 'interactiveOk') -ForegroundColor Green
  $FinalAcknowledge = Read-Host (Get-VanMsg 'interactiveFinalPrompt' @($cfg.FinalAcknowledgeTh))
  Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge
}

Invoke-VanDeployPreflight -App 'van2' -Target 'firestore'
Sync-VanFirestoreRules

Write-Host (Get-VanMsg 'firestoreSharedNote' @((Get-VanSharedImpactTh), $DatabaseId)) -ForegroundColor DarkYellow

if (-not (Test-Path $rulesFile)) {
  Write-Error "Missing rules file: $rulesFile"
  exit 1
}

$backupPath = Backup-VanFirestoreRules -SourcePath (Join-Path $appRoot $rulesFile) -Label 'firestore-default' -DryRun:$DryRun
$env:VAN_LAST_FIRESTORE_BACKUP = $backupPath

$tempConfig = '.firebase.firestore.van2.tmp.json'
$config = @{
  firestore = @{
    database = $DatabaseId
    rules    = $rulesFile
  }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfig -Encoding UTF8

try {
  Write-Host (Get-VanMsg 'firestoreDeploying' @($DatabaseId, $cfg.ProjectId)) -ForegroundColor Cyan
  if ($DryRun) {
    Write-Host (Get-VanMsg 'firestoreDryRun') -ForegroundColor Yellow
    return
  }
  firebase deploy --project $cfg.ProjectId --only firestore --config $tempConfig
}
finally {
  if (Test-Path $tempConfig) {
    Remove-Item $tempConfig -Force
  }
}
