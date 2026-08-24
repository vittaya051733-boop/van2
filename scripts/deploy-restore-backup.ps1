<#
.SYNOPSIS
  Restore deploy artifacts จาก session backup (rollback หลัง deploy พลาด)

.EXAMPLE
  .\deploy-restore-backup.ps1 -BackupDir "scripts\deploy-backups\sessions\20260811-172700\van2-firestore"

.EXAMPLE
  .\deploy-restore-backup.ps1 -SessionId 20260811-172700 -Step van2-firestore

.EXAMPLE
  .\deploy-restore-backup.ps1 -BackupDir "..." -DeployAfterRestore
#>
param(
  [string]$BackupDir,
  [string]$SessionId,
  [string]$Step,
  [switch]$DryRun,
  [switch]$DeployAfterRestore,
  [string]$FinalAcknowledge
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

if ([string]::IsNullOrWhiteSpace($FinalAcknowledge)) {
  $FinalAcknowledge = Get-VanAckTh
}

$backupRoot = Get-VanDeployBackupRoot

if (-not $BackupDir) {
  if (-not $SessionId) {
    $latestSession = Join-Path $backupRoot 'LATEST-SESSION.txt'
    if (Test-Path $latestSession) {
      foreach ($line in Get-Content $latestSession) {
        if ($line -match '^sessionId=(.+)$') {
          $SessionId = $Matches[1].Trim()
          break
        }
        if ($line -match '^lastStepDir=(.+)$') {
          $BackupDir = $Matches[1].Trim()
        }
      }
    }
  }

  if (-not $BackupDir -and $SessionId) {
    $sessionDir = Join-Path $backupRoot "sessions\$SessionId"
    if (-not (Test-Path $sessionDir)) {
      throw "Session not found: $sessionDir"
    }

    if ($Step) {
      $BackupDir = Join-Path $sessionDir $Step
    } else {
      $manifestPath = Join-Path $sessionDir 'manifest.json'
      if (-not (Test-Path $manifestPath)) {
        throw "Session manifest not found: $manifestPath"
      }
      $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
      $last = @($manifest.steps)[-1]
      if (-not $last) {
        throw "Session has no backup steps: $SessionId"
      }
      $BackupDir = $last.backupDir
    }
  }
}

if (-not $BackupDir) {
  throw 'Specify -BackupDir, -SessionId, or ensure LATEST-SESSION.txt exists.'
}

$resolvedDir = if ([System.IO.Path]::IsPathRooted($BackupDir)) {
  $BackupDir
} elseif ($BackupDir -match '^sessions\\') {
  Join-Path $backupRoot $BackupDir
} else {
  $BackupDir
}

if (-not (Test-Path $resolvedDir)) {
  throw "Backup directory not found: $resolvedDir"
}

$manifestPath = Join-Path $resolvedDir 'step-manifest.json'
if (-not (Test-Path $manifestPath)) {
  throw "Missing step-manifest.json in $resolvedDir"
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
Write-Host (Get-VanMsg 'restoreBackupTitle' @($manifest.app, $manifest.target, $resolvedDir)) -ForegroundColor Cyan

$restored = @()
foreach ($file in @($manifest.files)) {
  $src = Join-Path $resolvedDir $file.relativePath
  if (-not (Test-Path $src)) {
    throw "Missing backup file: $src"
  }

  $dest = if ($file.source) { $file.source } else {
    $cfg = Get-VanGovernanceConfig
    Join-Path $cfg.Apps[$manifest.app].Root $file.relativePath
  }

  if ($DryRun) {
    Write-Host (Get-VanMsg 'restoreDryRun' @($src, $dest)) -ForegroundColor Yellow
    continue
  }

  $destParent = Split-Path $dest -Parent
  if ($destParent -and -not (Test-Path $destParent)) {
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
  }
  Copy-Item -Path $src -Destination $dest -Force
  $restored += $dest
  Write-Host (Get-VanMsg 'restoreFileOk' @($file.relativePath)) -ForegroundColor Green
}

if ($manifest.app -eq 'van2' -and $manifest.target -eq 'firestore') {
  if (-not $DryRun) {
    Sync-VanFirestoreRules
    Write-Host (Get-VanMsg 'restoreFirestoreSynced') -ForegroundColor Green
  }
}

if ($DryRun) {
  exit 0
}

if (-not $DeployAfterRestore) {
  Write-Host (Get-VanMsg 'restoreManualDeploy') -ForegroundColor Yellow
  Write-Host "  deploy-self.ps1 -App $($manifest.app) -Target $($manifest.target) ..."
  exit 0
}

$selfArgs = @{
  App              = $manifest.app
  Target           = $manifest.target
  FinalAcknowledge = $FinalAcknowledge
  SkipReadiness    = $true
  SkipPreDeployBackup = $true
  ConfirmDeploy    = Get-VanDeployConfirmToken -App $manifest.app
}

if ($manifest.target -eq 'firestore') {
  $selfArgs.ConfirmImpact = (Get-VanGovernanceConfig).FirestoreSharedImpact
}
elseif ($manifest.target -eq 'functions' -and $manifest.functionNames) {
  $selfArgs.FunctionName = @($manifest.functionNames)
}

& (Join-Path $PSScriptRoot 'deploy-self.ps1') @selfArgs
exit $LASTEXITCODE
