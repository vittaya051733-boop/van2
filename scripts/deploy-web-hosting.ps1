param(
  [string]$ProjectId = 'van-merchant',
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$expectedConfirmation = "APPROVE:van2:$ProjectId"
if ($ConfirmDeploy -ne $expectedConfirmation) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmDeploy '$expectedConfirmation'"
  exit 1
}
Write-Host "[guard] Confirmation accepted: $expectedConfirmation" -ForegroundColor Green

$expectedFile = 'firebase.json'
$expectedImpact = 'SELF:van2'
if ($ConfirmFile -ne $expectedFile) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmFile '$expectedFile'"
  exit 1
}
if ($ConfirmImpact -ne $expectedImpact) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmImpact '$expectedImpact'"
  exit 1
}
Write-Host "[guard] File confirmation accepted: $expectedFile" -ForegroundColor Green
Write-Host "[guard] Impact confirmation accepted: $expectedImpact" -ForegroundColor Green

if ($InteractiveConfirm) {
  $interactiveFile = Read-Host "Interactive confirm file scope (expected: $expectedFile)"
  if ($interactiveFile -ne $expectedFile) {
    Write-Error "Interactive confirmation failed for file scope."
    exit 1
  }
  $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $expectedImpact)"
  if ($interactiveImpact -ne $expectedImpact) {
    Write-Error "Interactive confirmation failed for impact scope."
    exit 1
  }
  Write-Host "[interactive] File and impact confirmations accepted." -ForegroundColor Green
  $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: YES I UNDERSTAND)"
}

$expectedFinalAcknowledge = 'YES I UNDERSTAND'
if ($FinalAcknowledge -ne $expectedFinalAcknowledge) {
  Write-Error "Deployment blocked. Re-run with: -FinalAcknowledge '$expectedFinalAcknowledge'"
  exit 1
}
Write-Host "[guard] Final acknowledgement accepted." -ForegroundColor Green

flutter build web
if ($DryRun) {
  Write-Host '[dry-run] Skipping firebase deploy for hosting.' -ForegroundColor Yellow
  return
}
firebase deploy --only hosting --project $ProjectId