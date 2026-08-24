# Deploy ledger — append-only record of deploys / health runs

function Get-VanDeployLedgerPath {
  Join-Path (Get-VanDeployBackupRoot) 'LEDGER.jsonl'
}

function Write-VanDeployLedgerEntry {
  param(
    [Parameter(Mandatory)][string]$Kind,
    [string]$Bundle = '',
    [string]$App = '',
    [string]$Target = '',
    [string]$SessionId = '',
    [string]$Status = 'ok',
    [hashtable]$Extra = @{}
  )

  $root = Get-VanDeployBackupRoot
  if (-not (Test-Path $root)) {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
  }

  $entry = [ordered]@{
    ts        = (Get-Date -Format 'o')
    kind      = $Kind
    bundle    = $Bundle
    app       = $App
    target    = $Target
    sessionId = $(if ($SessionId) { $SessionId } else { $env:VAN_DEPLOY_SESSION_ID })
    status    = $Status
  }
  foreach ($k in $Extra.Keys) {
    $entry[$k] = $Extra[$k]
  }

  $line = ($entry | ConvertTo-Json -Compress -Depth 6)
  Add-Content -Path (Get-VanDeployLedgerPath) -Value $line -Encoding UTF8
}

function Show-VanDeployLedger {
  param([int]$Last = 20)

  $path = Get-VanDeployLedgerPath
  Write-Host ''
  Write-Host '=== Deploy Ledger (ล่าสุด) ===' -ForegroundColor Cyan
  if (-not (Test-Path $path)) {
    Write-Host '  (ยังไม่มีรายการ)' -ForegroundColor DarkGray
    Write-Host ''
    return
  }
  $lines = Get-Content $path -Encoding UTF8
  $slice = $lines | Select-Object -Last $Last
  foreach ($line in $slice) {
    try {
      $o = $line | ConvertFrom-Json
      Write-Host ("  {0} | {1,-12} | {2,-18} | {3}/{4} | {5}" -f $o.ts, $o.kind, $o.bundle, $o.app, $o.target, $o.status)
    }
    catch {
      Write-Host ("  {0}" -f $line) -ForegroundColor DarkGray
    }
  }
  Write-Host ''
  Write-Host ("ไฟล์: {0}" -f $path) -ForegroundColor Gray
  Write-Host ''
}
