<#
.SYNOPSIS
  Restore Firestore rules from deploy-backups (rollback after bad deploy).
#>
param(
  [string]$BackupFile,
  [switch]$DryRun,
  [switch]$DeployAfterRestore,
  [string]$FinalAcknowledge = 'YES I UNDERSTAND'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

$paths = Get-VanGovernanceRoot
$backupDir = Join-Path $paths.Van2Root 'scripts\deploy-backups'
$canonical = $paths.CanonicalRules

if (-not $BackupFile) {
  $latestManifest = Join-Path $backupDir 'LATEST.txt'
  if (-not (Test-Path $latestManifest)) {
    throw "No backup specified and LATEST.txt not found in $backupDir"
  }
  foreach ($line in Get-Content $latestManifest) {
    if ($line -match '^file=(.+)$') {
      $BackupFile = $Matches[1].Trim()
      break
    }
  }
  if (-not $BackupFile) {
    throw 'Could not read backup file name from LATEST.txt'
  }
}

$resolvedBackup = if ([System.IO.Path]::IsPathRooted($BackupFile)) {
  $BackupFile
} else {
  Join-Path $backupDir (Split-Path $BackupFile -Leaf)
}

if (-not (Test-Path $resolvedBackup)) {
  throw "Backup not found: $resolvedBackup"
}

Write-Host "[restore] Source backup: $resolvedBackup" -ForegroundColor Cyan

if ($DryRun) {
  Write-Host "[restore][dry-run] Would copy -> $canonical" -ForegroundColor Yellow
  exit 0
}

Copy-Item -Path $resolvedBackup -Destination $canonical -Force
Sync-VanFirestoreRules

Write-Host "[restore] Canonical rules restored from backup." -ForegroundColor Green

if (-not $DeployAfterRestore) {
  Write-Host 'Run deploy to push restored rules:'
  Write-Host '  deploy-plan.ps1 -App van2 -Target firestore -Execute'
  exit 0
}

& (Join-Path $PSScriptRoot 'deploy-self.ps1') `
  -App van2 -Target firestore `
  -ConfirmDeploy (Get-VanDeployConfirmToken -App 'van2') `
  -ConfirmImpact (Get-VanGovernanceConfig).FirestoreSharedImpact `
  -FinalAcknowledge $FinalAcknowledge `
  -SkipReadiness

exit $LASTEXITCODE
