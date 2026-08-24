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

$rulesFile = $cfg.FirestoreCanonicalFile

Assert-VanDeployConfirmation -App 'van2' -ConfirmDeploy $ConfirmDeploy
Assert-VanFileConfirmation -ConfirmFile $ConfirmFile -ExpectedFile $rulesFile
Assert-VanImpactConfirmation -ConfirmImpact $ConfirmImpact -ExpectedImpact $cfg.FirestoreSharedImpact
Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge

if ($InteractiveConfirm) {
  $interactiveFile = Read-Host "Interactive confirm file scope (expected: $rulesFile)"
  if ($interactiveFile -ne $rulesFile) {
    Write-Error 'Interactive confirmation failed for file scope.'
    exit 1
  }
  $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $($cfg.FirestoreSharedImpact))"
  if ($interactiveImpact -ne $cfg.FirestoreSharedImpact) {
    Write-Error 'Interactive confirmation failed for impact scope.'
    exit 1
  }
  Write-Host '[interactive] File and impact confirmations accepted.' -ForegroundColor Green
  $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: $($cfg.FinalAcknowledge))"
  Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge
}

Invoke-VanDeployPreflight -App 'van2' -Target 'firestore'
Sync-VanFirestoreRules

Write-Host "Firestore rules are shared by $($cfg.FirestoreSharedImpact) on database '$DatabaseId'." -ForegroundColor DarkYellow

if (-not (Test-Path $rulesFile)) {
  Write-Error "Missing rules file: $rulesFile"
  exit 1
}

$tempConfig = '.firebase.firestore.van2.tmp.json'
$config = @{
  firestore = @{
    database = $DatabaseId
    rules    = $rulesFile
  }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $tempConfig -Encoding UTF8

try {
  Write-Host "Deploying Firestore rules to database '$DatabaseId' in project '$($cfg.ProjectId)'" -ForegroundColor Cyan
  if ($DryRun) {
    Write-Host '[dry-run] Skipping firebase deploy for firestore rules.' -ForegroundColor Yellow
    return
  }
  firebase deploy --project $cfg.ProjectId --only firestore --config $tempConfig
}
finally {
  if (Test-Path $tempConfig) {
    Remove-Item $tempConfig -Force
  }
}
