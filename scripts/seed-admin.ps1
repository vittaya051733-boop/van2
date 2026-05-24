param(
  [Parameter(Mandatory)]
  [string]$Email,

  [Parameter(Mandatory)]
  [string]$Password,

  [string]$DisplayName = 'Van Market Admin',
  [string]$ProjectId = 'van-merchant'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$nodeScript = Join-Path $scriptRoot 'seed-admin.mjs'

if (-not (Test-Path $nodeScript)) {
  throw "Missing $nodeScript"
}

Write-Host "Seeding admin for project $ProjectId ..." -ForegroundColor Cyan
Write-Host "Password is stored in Firebase Auth only (not Firestore)." -ForegroundColor Yellow

node $nodeScript `
  --email $Email `
  --password $Password `
  --name $DisplayName `
  --project $ProjectId
