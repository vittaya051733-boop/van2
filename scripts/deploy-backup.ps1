function Get-VanDeployBackupRoot {
  $paths = Get-VanGovernanceRoot
  Join-Path $paths.Van2Root 'scripts\deploy-backups'
}

function Get-VanDeployBackupSessionId {
  param([switch]$ForceNew)
  if (-not $ForceNew -and $env:VAN_DEPLOY_SESSION_ID) {
    return $env:VAN_DEPLOY_SESSION_ID.Trim()
  }
  $id = Get-Date -Format 'yyyyMMdd-HHmmss'
  $env:VAN_DEPLOY_SESSION_ID = $id
  return $id
}

function Backup-VanDeployTarget {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('van1', 'van2', 'van3', 'van4')]
    [string]$App,
    [Parameter(Mandatory = $true)]
    [ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')]
    [string]$Target,
    [switch]$DryRun
  )

  $cfg = Get-VanGovernanceConfig
  $appRoot = $cfg.Apps[$App].Root
  $artifacts = @()

  if ($Target -eq 'storage') {
    $path = Join-Path $appRoot 'storage.rules'
    if (Test-Path $path) {
      $artifacts += ,@{ Path = $path; RelativePath = 'storage.rules' }
    }
  }
  elseif ($Target -eq 'firestore') {
    $rules = Join-Path $appRoot $cfg.FirestoreCanonicalFile
    if (Test-Path $rules) {
      $artifacts += ,@{ Path = $rules; RelativePath = $cfg.FirestoreCanonicalFile }
    }
    $indexes = Join-Path $appRoot 'firestore.indexes.json'
    if (Test-Path $indexes) {
      $artifacts += ,@{ Path = $indexes; RelativePath = 'firestore.indexes.json' }
    }
  }
  elseif ($Target -eq 'firestore-van4') {
    $path = Join-Path $appRoot 'firestore.rules'
    if (Test-Path $path) {
      $artifacts += ,@{ Path = $path; RelativePath = 'firestore.rules' }
    }
  }
  elseif ($Target -eq 'hosting') {
    $path = Join-Path $appRoot 'firebase.json'
    if (Test-Path $path) {
      $artifacts += ,@{ Path = $path; RelativePath = 'firebase.json' }
    }
  }
  elseif ($Target -eq 'functions') {
    $functionsRoot = Join-Path $appRoot 'functions'
    $indexJs = Join-Path $functionsRoot 'index.js'
    if (Test-Path $indexJs) {
      $artifacts += ,@{ Path = $indexJs; RelativePath = 'functions/index.js' }
    }
    if (Test-Path $functionsRoot) {
      Get-ChildItem -Path $functionsRoot -Filter '*.js' -File -Recurse |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
        ForEach-Object {
          $relative = $_.FullName.Substring($appRoot.Length).TrimStart('\').TrimStart('/')
          if ($relative -ne 'functions/index.js') {
            $artifacts += ,@{ Path = $_.FullName; RelativePath = $relative }
          }
        }
    }
  }

  if ($artifacts.Count -eq 0) {
    throw "Cannot backup - no deploy artifacts found for $App / $Target"
  }

  $sessionId = Get-VanDeployBackupSessionId
  $backupRoot = Get-VanDeployBackupRoot
  $sessionDir = Join-Path $backupRoot "sessions\$sessionId"
  $targetDir = Join-Path $sessionDir "$App-$Target"
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

  if ($DryRun) {
    Write-Host (Get-VanMsg 'backupSessionDryRun' @($sessionId, "$App/$Target", $targetDir)) -ForegroundColor Yellow
    return $targetDir
  }

  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  $entries = @()
  foreach ($artifact in $artifacts) {
    $dest = Join-Path $targetDir $artifact.RelativePath
    $destParent = Split-Path $dest -Parent
    if ($destParent -and -not (Test-Path $destParent)) {
      New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    }
    Copy-Item -Path $artifact.Path -Destination $dest -Force
    $entries += @{
      relativePath = $artifact.RelativePath
      source       = $artifact.Path
      sha256       = (Get-FileHash $artifact.Path -Algorithm SHA256).Hash
    }
  }

  @{
    timestamp     = $stamp
    sessionId     = $sessionId
    app           = $App
    target        = $Target
    functionNames = @()
    files         = $entries
  } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $targetDir 'step-manifest.json') -Encoding UTF8

  $sessionManifestPath = Join-Path $sessionDir 'manifest.json'
  $sessionManifest = if (Test-Path $sessionManifestPath) {
    Get-Content $sessionManifestPath -Raw | ConvertFrom-Json
  } else {
    @{ sessionId = $sessionId; createdAt = $stamp; steps = @() }
  }
  if ($sessionManifest.steps -isnot [System.Collections.IList]) {
    $sessionManifest.steps = @($sessionManifest.steps)
  }
  $sessionManifest.steps += @{
    app       = $App
    target    = $Target
    backupDir = $targetDir
    timestamp = $stamp
    fileCount = $entries.Count
  }
  $sessionManifest | ConvertTo-Json -Depth 8 | Set-Content -Path $sessionManifestPath -Encoding UTF8

  @(
    "sessionId=$sessionId"
    "lastApp=$App"
    "lastTarget=$Target"
    "lastStepDir=$targetDir"
    "timestamp=$stamp"
  ) | Set-Content -Path (Join-Path $backupRoot 'LATEST-SESSION.txt') -Encoding UTF8

  if ($Target -eq 'firestore' -and $App -eq 'van2') {
    $rulesArtifact = $artifacts | Where-Object { $_.RelativePath -eq 'firestore.rules' } | Select-Object -First 1
    if ($rulesArtifact) {
      $hash = (Get-FileHash $rulesArtifact.Path -Algorithm SHA256).Hash
      $legacyName = "firestore-default-${stamp}-$($hash.Substring(0, 12)).rules"
      Copy-Item -Path $rulesArtifact.Path -Destination (Join-Path $backupRoot $legacyName) -Force
      @(
        "timestamp=$stamp"
        "label=firestore-default"
        "file=$legacyName"
        "sha256=$hash"
        "source=$($rulesArtifact.Path)"
        "sessionId=$sessionId"
      ) | Set-Content -Path (Join-Path $backupRoot 'LATEST.txt') -Encoding UTF8
    }
  }

  Write-Host (Get-VanMsg 'backupSessionSaved' @($sessionId, "$App/$Target", $targetDir, $entries.Count)) -ForegroundColor Green
  return $targetDir
}

function Initialize-VanDeployBatchSession {
  param([switch]$DryRun)
  $sessionId = Get-VanDeployBackupSessionId -ForceNew
  $sessionDir = Join-Path (Get-VanDeployBackupRoot) "sessions\$sessionId"
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
  }
  Write-Host (Get-VanMsg 'batchSessionStarted' @($sessionId, $sessionDir)) -ForegroundColor Cyan
  return @{ sessionId = $sessionId; sessionDir = $sessionDir }
}

function Backup-VanDeployBatchSteps {
  param(
    [Parameter(Mandatory = $true)][object[]]$Steps,
    [switch]$DryRun
  )
  $backups = @()
  foreach ($step in $Steps) {
    $backupDir = Backup-VanDeployTarget -App $step.App -Target $step.Target -DryRun:$DryRun
    $backups += @{ app = $step.App; target = $step.Target; backupDir = $backupDir; functionName = @($step.FunctionName) }
    $env:VAN_PREDEPLOY_BACKUP_DONE = $null
  }
  return $backups
}

function Parse-VanDeployBatchStep {
  param([Parameter(Mandatory = $true)][string]$Step)
  $parts = $Step.Split(':')
  if ($parts.Count -lt 2) {
    throw "Invalid batch step '$Step'. Use vanN:target or vanN:functions:name"
  }
  $app = $parts[0].Trim()
  $target = $parts[1].Trim()
  $fn = @()
  if ($target -eq 'functions') {
    if ($parts.Count -lt 3) { throw 'Functions step requires names' }
    $fn = $parts[2].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
  return @{ App = $app; Target = $target; FunctionName = $fn }
}

function Invoke-VanPreDeployBackup {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory = $true)][ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')][string]$Target,
    [string[]]$FunctionName = @(),
    [switch]$DryRun
  )
  if ($DryRun) {
    return Backup-VanDeployTarget -App $App -Target $Target -DryRun
  }
  $marker = "$App`:$Target"
  if ($env:VAN_PREDEPLOY_BACKUP_DONE -eq $marker) { return $null }
  $path = Backup-VanDeployTarget -App $App -Target $Target
  $env:VAN_PREDEPLOY_BACKUP_DONE = $marker
  $env:VAN_LAST_DEPLOY_BACKUP_DIR = $path
  if ($Target -eq 'firestore' -and $App -eq 'van2' -and (Test-Path (Join-Path (Get-VanDeployBackupRoot) 'LATEST.txt'))) {
    foreach ($line in Get-Content (Join-Path (Get-VanDeployBackupRoot) 'LATEST.txt')) {
      if ($line -match '^file=(.+)$') {
        $env:VAN_LAST_FIRESTORE_BACKUP = Join-Path (Get-VanDeployBackupRoot) $Matches[1].Trim()
        break
      }
    }
  }
  return $path
}

function Backup-VanFirestoreRules {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$DryRun
  )
  if ($env:VAN_PREDEPLOY_BACKUP_DONE -eq 'van2:firestore') {
    if ($env:VAN_LAST_FIRESTORE_BACKUP) { return $env:VAN_LAST_FIRESTORE_BACKUP }
    return $env:VAN_LAST_DEPLOY_BACKUP_DIR
  }
  if (-not (Test-Path $SourcePath)) {
    throw "Cannot backup - missing rules file: $SourcePath"
  }
  return Backup-VanDeployTarget -App 'van2' -Target 'firestore' -DryRun:$DryRun
}
