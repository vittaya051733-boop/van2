param(
  [switch]$FirestoreOnly,
  [switch]$StorageOnly
)

$ErrorActionPreference = 'Stop'

Write-Error 'BLOCKED: Shared deploy script is disabled. Read van2/scripts/DEPLOY_GOVERNANCE.md and use deploy-safe.ps1 or deploy-*-isolated.ps1 instead.'
exit 1
