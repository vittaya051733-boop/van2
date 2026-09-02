param(
  [Parameter(Mandatory)]
  [string]$Email,

  [string]$Password,

  [string]$DisplayName = 'Van Market Admin',
  [ValidateSet('super_admin', 'branch_admin')]
  [string]$Role = 'branch_admin',
  [string]$BranchId,
  [string]$ProjectId = 'van-merchant',
  [switch]$FirestoreOnly,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$nodeScript = Join-Path $scriptRoot 'seed-admin.mjs'

if (-not (Test-Path $nodeScript)) {
  throw "Missing $nodeScript"
}

if ($Role -eq 'branch_admin' -and [string]::IsNullOrWhiteSpace($BranchId)) {
  throw 'branch_admin ต้องระบุ -BranchId'
}
if (-not $FirestoreOnly -and [string]::IsNullOrWhiteSpace($Password)) {
  throw 'ต้องระบุ -Password หรือใช้ -FirestoreOnly'
}

Write-Host "Seeding admin for project $ProjectId ..." -ForegroundColor Cyan
Write-Host "Password is stored in Firebase Auth only (not Firestore)." -ForegroundColor Yellow

$args = @(
  '--email', $Email,
  '--name', $DisplayName,
  '--role', $Role,
  '--project', $ProjectId
)
if ($Password) { $args += @('--password', $Password) }
if ($BranchId) { $args += @('--branch-id', $BranchId) }
if ($FirestoreOnly) { $args += '--firestore-only' }
if ($DryRun) { $args += '--dry-run' }

node $nodeScript @args
