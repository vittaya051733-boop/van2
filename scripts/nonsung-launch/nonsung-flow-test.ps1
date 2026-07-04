<#
.SYNOPSIS
  Phase 1 - 4-app flow test + pilot readiness for Non Sung market

.EXAMPLE
  .\nonsung-flow-test.ps1
  .\nonsung-flow-test.ps1 -SkipEmulator -SkipPilot
#>
param(
  [switch]$SkipEmulator,
  [switch]$SkipPilot,
  [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$van2Scripts = Split-Path $PSScriptRoot -Parent
$pilotScript = Join-Path $van2Scripts 'soft-launch-pilot-test.ps1'

Write-Host '=== Non Sung - 4-app flow test (Phase 1) ===' -ForegroundColor Cyan

if (-not $SkipPilot) {
  if (-not (Test-Path $pilotScript)) {
    throw "Missing pilot script: $pilotScript"
  }
  $pilotArgs = @()
  if ($SkipEmulator) { $pilotArgs += '-SkipEmulator' }
  if ($Strict) { $pilotArgs += '-Strict' }
  & $pilotScript @pilotArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Pilot test failed (exit $LASTEXITCODE)"
  }
}

Write-Host ''
Write-Host '--- Manual E2E checklist (Non Sung market) ---' -ForegroundColor Yellow
$steps = @(
  'van2: login -> pick shop in zone -> enter delivery address'
  'van2: checkout COD or PromptPay -> confirm order'
  'van1: shop sees order -> accept -> preparing -> ready'
  'van3: rider onlineReady -> accept -> deliver complete'
  'van4: order visible -> export CSV -> check settlement fee'
  'van2: coupon NONSUNG50 after seed -> shipping discount in cart'
  'van2: no rider online -> rider unavailable dialog'
)
$i = 1
foreach ($step in $steps) {
  Write-Host "  [$i] $step"
  $i++
}

Write-Host ''
Write-Host 'Log results: nonsung-kpi-weekly.csv (20 pilot orders)' -ForegroundColor Green
Write-Host 'Survey: nonsung-shop-survey.csv (50) + nonsung-rider-registry.csv (8)' -ForegroundColor Green
