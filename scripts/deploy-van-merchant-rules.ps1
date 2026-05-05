param(
  [switch]$FirestoreOnly,
  [switch]$StorageOnly
)

$ErrorActionPreference = 'Stop'

Write-Error 'BLOCKED: Shared deploy script is disabled to prevent cross-app impact. Use isolated scripts/tasks instead: deploy-firestore-isolated.ps1 or deploy-storage-isolated.ps1.'
exit 1
