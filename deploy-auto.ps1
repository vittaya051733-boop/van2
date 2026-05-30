param(
  [switch]$IncludeApp,
  [switch]$ForceLegacy
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host 'BLOCKED: deploy-auto.ps1 deploys multiple targets without isolated guards.' -ForegroundColor Red
Write-Host ''
Write-Host 'Use instead (one target at a time):' -ForegroundColor Yellow
Write-Host '  van2\scripts\deploy-readiness.ps1 -App van2 -Target storage'
Write-Host '  van2\scripts\deploy-self.ps1 -App van2 -Target storage -ConfirmDeploy ... -FinalAcknowledge "YES I UNDERSTAND"'
Write-Host ''
Write-Host 'Read: van2\scripts\DEPLOY_GOVERNANCE.md + DEPLOY_RISK_MATRIX.md' -ForegroundColor Cyan
Write-Host ''

if (-not $ForceLegacy) {
  exit 1
}

Write-Warning 'ForceLegacy enabled — proceeding with deprecated combined deploy.'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

powershell -ExecutionPolicy Bypass -File 'scripts/deploy-firestore-isolated.ps1'
powershell -ExecutionPolicy Bypass -File 'scripts/deploy-storage-isolated.ps1'

if ($IncludeApp) {
  powershell -ExecutionPolicy Bypass -File 'scripts/deploy-isolated.ps1'
}

Write-Host '[AUTO] Done (legacy).' -ForegroundColor Green
