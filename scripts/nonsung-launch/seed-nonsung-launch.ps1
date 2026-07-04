param(
  [switch]$DryRun,
  [string]$ConfirmSeed = '',
  [string]$PaymentName = 'วิทยา ทนหงษา',
  [string]$PaymentBank = 'ธนาคารกสิกรไทย',
  [string]$PaymentAccount = '1643440349',
  [string]$PromptPayId = '1410400168710',
  [string]$PromptPayPhone = ''
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$nodeScript = Join-Path $scriptDir 'seed-nonsung-launch-config.js'

if (-not (Test-Path $nodeScript)) {
  throw "Missing $nodeScript"
}

$nodeArgs = @($nodeScript)
if ($DryRun) {
  $nodeArgs += '--dry-run'
} elseif ($ConfirmSeed) {
  $nodeArgs += '--confirm'
  $nodeArgs += $ConfirmSeed
  $nodeArgs += '--payment-name'
  $nodeArgs += $PaymentName
  $nodeArgs += '--payment-bank'
  $nodeArgs += $PaymentBank
  $nodeArgs += '--payment-account'
  $nodeArgs += $PaymentAccount
  if ($PromptPayId) {
    $nodeArgs += '--promptpay-id'
    $nodeArgs += $PromptPayId
  }
  if ($PromptPayPhone) {
    $nodeArgs += '--promptpay-phone'
    $nodeArgs += $PromptPayPhone
  }
} else {
  Write-Host 'Dry-run mode (default). Use -ConfirmSeed APPROVE:nonsung:van-merchant to write.' -ForegroundColor Yellow
  $nodeArgs += '--dry-run'
}

Write-Host 'Non Sung launch config seed' -ForegroundColor Cyan
Write-Host 'Requires: gcloud auth application-default login' -ForegroundColor Yellow
node @nodeArgs
