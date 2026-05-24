param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

  [Parameter(Mandatory = $true)]
  [string]$ConfirmDeploy,

  [Parameter(Mandatory = $true)]
  [string]$ConfirmFile,

  [Parameter(Mandatory = $true)]
  [string]$ConfirmImpact,

  [Parameter(Mandatory = $false)]
  [switch]$InteractiveConfirm,

  [Parameter(Mandatory = $false)]
  [string]$FinalAcknowledge,

  [Parameter(Mandatory = $false)]
  [switch]$DryRun,

  [Parameter(Mandatory = $true)]
  [string]$BillingAccount,

  [Parameter(Mandatory = $true)]
  [string]$GoogleRoutesApiKey,

  [Parameter(Mandatory = $false)]
  [string]$RedisUrl = "",

  [Parameter(Mandatory = $false)]
  [string]$RedisToken = "",

  [Parameter(Mandatory = $false)]
  [string]$RedisRestUrl = "",

  [Parameter(Mandatory = $false)]
  [string]$RedisRestToken = "",

  [Parameter(Mandatory = $false)]
  [string]$FunctionsDir = "C:/Users/TAM/Desktop/van2/_github_my_flutter/functions",

  [Parameter(Mandatory = $false)]
  [string]$BudgetDisplayName = "Van Market Budget Alert",

  [Parameter(Mandatory = $false)]
  [decimal]$BudgetAmountUsd = 20
)

$ErrorActionPreference = "Stop"

$expectedConfirmation = "APPROVE:van2:$ProjectId"
if ($ConfirmDeploy -ne $expectedConfirmation) {
  throw "Deployment blocked. Re-run with: -ConfirmDeploy '$expectedConfirmation'"
}
Write-Host "[guard] Confirmation accepted: $expectedConfirmation" -ForegroundColor Green

$expectedFile = 'functions'
$expectedImpact = 'SELF:van2'
if ($ConfirmFile -ne $expectedFile) {
  throw "Deployment blocked. Re-run with: -ConfirmFile '$expectedFile'"
}
if ($ConfirmImpact -ne $expectedImpact) {
  throw "Deployment blocked. Re-run with: -ConfirmImpact '$expectedImpact'"
}
Write-Host "[guard] File confirmation accepted: $expectedFile" -ForegroundColor Green
Write-Host "[guard] Impact confirmation accepted: $expectedImpact" -ForegroundColor Green

if ($InteractiveConfirm) {
  $interactiveFile = Read-Host "Interactive confirm file scope (expected: $expectedFile)"
  if ($interactiveFile -ne $expectedFile) {
    throw "Interactive confirmation failed for file scope."
  }
  $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $expectedImpact)"
  if ($interactiveImpact -ne $expectedImpact) {
    throw "Interactive confirmation failed for impact scope."
  }
  Write-Host "[interactive] File and impact confirmations accepted." -ForegroundColor Green
  $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: YES I UNDERSTAND)"
}

$expectedFinalAcknowledge = 'YES I UNDERSTAND'
if ($FinalAcknowledge -ne $expectedFinalAcknowledge) {
  throw "Deployment blocked. Re-run with: -FinalAcknowledge '$expectedFinalAcknowledge'"
}
Write-Host "[guard] Final acknowledgement accepted." -ForegroundColor Green

function Assert-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Command '$name' was not found. Install it before running this script."
  }
}

Write-Host "== Checking required tools ==" -ForegroundColor Cyan
Assert-Command "gcloud"
Assert-Command "firebase"

Write-Host "== Setting project ==" -ForegroundColor Cyan
gcloud config set project $ProjectId | Out-Null

Write-Host "== Enabling required APIs ==" -ForegroundColor Cyan
gcloud services enable routes.googleapis.com --project $ProjectId
gcloud services enable cloudfunctions.googleapis.com --project $ProjectId
gcloud services enable secretmanager.googleapis.com --project $ProjectId
gcloud services enable billingbudgets.googleapis.com --project $ProjectId

Write-Host "== Setting Firebase Functions secrets ==" -ForegroundColor Cyan
Push-Location $FunctionsDir
try {
  $GoogleRoutesApiKey | firebase functions:secrets:set GOOGLE_ROUTES_API_KEY --project $ProjectId

  if (-not [string]::IsNullOrWhiteSpace($RedisUrl)) {
    $RedisUrl | firebase functions:secrets:set REDIS_URL --project $ProjectId
  } else {
    Write-Host "Skipping REDIS_URL (not provided)." -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisToken)) {
    $RedisToken | firebase functions:secrets:set REDIS_TOKEN --project $ProjectId
  } else {
    Write-Host "Skipping REDIS_TOKEN (not provided)." -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisRestUrl)) {
    $RedisRestUrl | firebase functions:secrets:set REDIS_REST_URL --project $ProjectId
  } else {
    Write-Host "Skipping REDIS_REST_URL (not provided)." -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisRestToken)) {
    $RedisRestToken | firebase functions:secrets:set REDIS_REST_TOKEN --project $ProjectId
  } else {
    Write-Host "Skipping REDIS_REST_TOKEN (not provided)." -ForegroundColor Yellow
  }

  Write-Host "== Deploying computeRouteMetrics function ==" -ForegroundColor Cyan
  if ($DryRun) {
    Write-Host "[dry-run] Skipping firebase deploy for computeRouteMetrics." -ForegroundColor Yellow
  } else {
    firebase deploy --only functions:computeRouteMetrics --project $ProjectId
  }
}
finally {
  Pop-Location
}

Write-Host "== Creating budget alerts ==" -ForegroundColor Cyan
$amount = "{0}USD" -f $BudgetAmountUsd
gcloud beta billing budgets create `
  --billing-account=$BillingAccount `
  --display-name=$BudgetDisplayName `
  --budget-amount=$amount `
  --threshold-rule=percent=0.5 `
  --threshold-rule=percent=1.0

Write-Host "== Verifying results ==" -ForegroundColor Cyan
gcloud services list --enabled --project $ProjectId | Select-String "routes.googleapis.com"
firebase functions:list --project $ProjectId
gcloud beta billing budgets list --billing-account=$BillingAccount

Write-Host "Done: APIs enabled, secrets set, function deployed, and budget alerts created." -ForegroundColor Green
