param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

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

function Assert-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "ไม่พบคำสั่ง '$name' กรุณาติดตั้งก่อนใช้งาน"
  }
}

Write-Host "== ตรวจสอบเครื่องมือ ==" -ForegroundColor Cyan
Assert-Command "gcloud"
Assert-Command "firebase"

Write-Host "== ตั้งค่าโปรเจกต์ ==" -ForegroundColor Cyan
gcloud config set project $ProjectId | Out-Null

Write-Host "== เปิด API ที่ต้องใช้ ==" -ForegroundColor Cyan
gcloud services enable routes.googleapis.com --project $ProjectId
gcloud services enable cloudfunctions.googleapis.com --project $ProjectId
gcloud services enable secretmanager.googleapis.com --project $ProjectId
gcloud services enable billingbudgets.googleapis.com --project $ProjectId

Write-Host "== ตั้งค่า Firebase Functions Secrets ==" -ForegroundColor Cyan
Push-Location $FunctionsDir
try {
  $GoogleRoutesApiKey | firebase functions:secrets:set GOOGLE_ROUTES_API_KEY --project $ProjectId

  if (-not [string]::IsNullOrWhiteSpace($RedisUrl)) {
    $RedisUrl | firebase functions:secrets:set REDIS_URL --project $ProjectId
  } else {
    Write-Host "ข้าม REDIS_URL (ไม่ได้ระบุ)" -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisToken)) {
    $RedisToken | firebase functions:secrets:set REDIS_TOKEN --project $ProjectId
  } else {
    Write-Host "ข้าม REDIS_TOKEN (ไม่ได้ระบุ)" -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisRestUrl)) {
    $RedisRestUrl | firebase functions:secrets:set REDIS_REST_URL --project $ProjectId
  } else {
    Write-Host "ข้าม REDIS_REST_URL (ไม่ได้ระบุ)" -ForegroundColor Yellow
  }

  if (-not [string]::IsNullOrWhiteSpace($RedisRestToken)) {
    $RedisRestToken | firebase functions:secrets:set REDIS_REST_TOKEN --project $ProjectId
  } else {
    Write-Host "ข้าม REDIS_REST_TOKEN (ไม่ได้ระบุ)" -ForegroundColor Yellow
  }

  Write-Host "== Deploy ฟังก์ชัน computeRouteMetrics ==" -ForegroundColor Cyan
  firebase deploy --only functions:computeRouteMetrics --project $ProjectId
}
finally {
  Pop-Location
}

Write-Host "== สร้าง Budget Alerts ==" -ForegroundColor Cyan
$amount = "{0}USD" -f $BudgetAmountUsd
gcloud beta billing budgets create `
  --billing-account=$BillingAccount `
  --display-name=$BudgetDisplayName `
  --budget-amount=$amount `
  --threshold-rule=percent=0.5 `
  --threshold-rule=percent=1.0

Write-Host "== ตรวจสอบผลลัพธ์ ==" -ForegroundColor Cyan
gcloud services list --enabled --project $ProjectId | Select-String "routes.googleapis.com"
firebase functions:list --project $ProjectId
gcloud beta billing budgets list --billing-account=$BillingAccount

Write-Host "เสร็จสิ้น: เปิด Routes API + ตั้ง Secrets + Deploy + ตั้ง Budget Alerts เรียบร้อย" -ForegroundColor Green
