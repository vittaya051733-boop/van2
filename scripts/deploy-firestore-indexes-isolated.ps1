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

$indexesFile = 'firestore.indexes.json'

Assert-VanDeployConfirmation -App 'van2' -ConfirmDeploy $ConfirmDeploy
Assert-VanFileConfirmation -ConfirmFile $ConfirmFile -ExpectedFile $indexesFile
Assert-VanImpactConfirmation -ConfirmImpact $ConfirmImpact -ExpectedImpact $cfg.FirestoreSharedImpact
Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge

if ($InteractiveConfirm) {
  $expectedImpactTh = ConvertTo-VanImpactTokenTh $cfg.FirestoreSharedImpact
  $interactiveFile = Read-Host (Get-VanMsg 'interactiveFilePrompt' @($indexesFile))
  if ($interactiveFile -ne $indexesFile) {
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

Write-Host (Get-VanMsg 'firestoreSharedNote' @((Get-VanSharedImpactTh), $DatabaseId)) -ForegroundColor DarkYellow

if (-not (Test-Path $indexesFile)) {
  Write-Error "Missing indexes file: $indexesFile"
  exit 1
}

$tempConfig = '.firebase.firestore-indexes.van2.tmp.json'
$config = @{
  firestore = @{
    database = $DatabaseId
    indexes  = $indexesFile
  }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfig -Encoding UTF8

try {
  Write-Host "Deploying Firestore indexes only ($DatabaseId) to $($cfg.ProjectId)..." -ForegroundColor Cyan
  if ($DryRun) {
    Write-Host '[dry-run] Skipping firebase deploy for firestore:indexes' -ForegroundColor Yellow
    return
  }
  firebase deploy --project $cfg.ProjectId --only firestore:indexes --config $tempConfig
}
finally {
  if (Test-Path $tempConfig) {
    Remove-Item $tempConfig -Force
  }
}
