param(
  [switch]$SnapshotOnly,
  [switch]$SkipSnapshot
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$snapshot = Join-Path $scriptDir 'nonsung-ops-snapshot.mjs'

$hour = (Get-Date).Hour
$slot = if ($hour -lt 12) { '09:00' } elseif ($hour -lt 17) { '12:00' } else { '18:00' }

Write-Host "=== Non Sung daily ops ($slot slot) ===" -ForegroundColor Cyan

if (-not $SkipSnapshot -and (Test-Path $snapshot)) {
  try {
    node $snapshot
  } catch {
    Write-Host "Snapshot skipped (ADC?): $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

if ($SnapshotOnly) { exit 0 }

Write-Host ''
Write-Host 'Checklist:' -ForegroundColor Yellow
$items = @(
  '09:00 — van4: ออเดอร์ค้าง awaiting_rider / preparing',
  '12:00 — ไรเดอร์ onlineReady ≥ 2 (peak 16:00–20:00 ต้อง ≥ 3)',
  '18:00 — สรุปออเดอร์วัน → nonsung-kpi-weekly.csv',
  '18:00 — โทรร้านที่ pause ออเดอร์',
  'อาทิตย์ — ประชุม 30 นาที 3 ขา (ร้าน / ไรเดอร์ / tech)'
)
foreach ($item in $items) {
  $mark = if ($item.StartsWith($slot)) { '[NOW]' } else { '     ' }
  Write-Host "$mark $item"
}

Write-Host ''
Write-Host 'Files: nonsung-kpi-weekly.csv | van4 CSV export | LINE groups (nonsung-line-groups.md)' -ForegroundColor Green
