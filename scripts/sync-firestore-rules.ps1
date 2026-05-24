param(
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

Write-Host 'Syncing canonical Firestore rules (van2) to van1 and van3...' -ForegroundColor Cyan
Sync-VanFirestoreRules -WhatIf:$WhatIf

if ($WhatIf) {
  Write-Host '[sync] WhatIf complete. Re-run without -WhatIf to apply.' -ForegroundColor Yellow
} else {
  Write-Host '[sync] All targets match canonical hash.' -ForegroundColor Green
}
