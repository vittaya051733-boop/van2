param(
  [ValidateSet('prep', 'soft', 'expand', 'review', 'all')]
  [string]$Phase = 'all'
)

$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

$phases = @{
  prep = @{
    Title = 'Phase 1 — Prep (วัน 1–14)'
    Files = @(
      'nonsung-flow-test.ps1'
      'nonsung-shop-survey.csv'
      'nonsung-rider-registry.csv'
      'seed-nonsung-launch.ps1'
      'nonsung-line-groups.md'
    )
    Actions = @(
      'Run: .\nonsung-flow-test.ps1'
      'Run: .\seed-nonsung-launch.ps1 -DryRun then -ConfirmSeed'
      'Fill 50 shops + 8 riders in CSV'
      'Create LINE groups'
      '20 test orders in market'
    )
  }
  soft = @{
    Title = 'Phase 2 — Soft launch (วัน 15–45)'
    Files = @(
      'nonsung-poster-brief.md'
      'nonsung-kpi-weekly.csv'
      'nonsung-ops-daily.ps1'
      'seed-nonsung-launch-config.js'
    )
    Actions = @(
      'NONSUNG50 live (seed)'
      'Onboard 20–28 shops'
      'QR posters 2–3 dorms'
      'Daily: nonsung-ops-daily.ps1'
      'Weekly KPI in nonsung-kpi-weekly.csv'
    )
  }
  expand = @{
    Title = 'Phase 3 — Expand (วัน 46–75)'
    Files = @(
      'nonsung-college-campaign.md'
      'nonsung-ops-snapshot.mjs'
    )
    Actions = @(
      'College + 5–10 dorms'
      'Late-night Fri–Sun 19–22'
      'van4 CSV review 18:00 daily'
    )
  }
  review = @{
    Title = 'Phase 4 — Review (วัน 76–90)'
    Files = @(
      'nonsung-day90-review.md'
      'nonsung-playbook.md'
      'nonsung-unit-economics.csv'
    )
    Actions = @(
      'Fill day90 review doc'
      'Unit economics weekly rows'
      'Decide expand vs narrow'
    )
  }
}

function Show-Phase($key) {
  $p = $phases[$key]
  Write-Host "`n=== $($p.Title) ===" -ForegroundColor Cyan
  Write-Host 'Files:'
  foreach ($f in $p.Files) {
    $path = Join-Path $dir $f
    $ok = Test-Path $path
    $mark = if ($ok) { '[OK]' } else { '[MISSING]' }
    Write-Host "  $mark $f"
  }
  Write-Host 'Actions:'
  foreach ($a in $p.Actions) {
    Write-Host "  - $a"
  }
}

if ($Phase -eq 'all') {
  foreach ($k in @('prep', 'soft', 'expand', 'review')) {
    Show-Phase $k
  }
} else {
  Show-Phase $Phase
}

Write-Host "`nHub: $dir\README.md" -ForegroundColor Green
