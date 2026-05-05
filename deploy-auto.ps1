param(
  [switch]$IncludeApp
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host '[AUTO] Deploy Firestore Isolated (van2)' -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File 'scripts/deploy-firestore-isolated.ps1'

Write-Host '[AUTO] Deploy Storage Isolated (van2)' -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File 'scripts/deploy-storage-isolated.ps1'

if ($IncludeApp) {
  Write-Host '[AUTO] Deploy App Isolated (van2)' -ForegroundColor Cyan
  powershell -ExecutionPolicy Bypass -File 'scripts/deploy-isolated.ps1'
}

Write-Host '[AUTO] Done.' -ForegroundColor Green
