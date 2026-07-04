# Single source of truth for van1–van4 deploy policy on project van-merchant.
# Dot-source: Import-VanDeployGovernance -CallingScriptRoot $PSScriptRoot

$ErrorActionPreference = 'Stop'

function Import-VanDeployGovernance {
  param([string]$CallingScriptRoot = $PSScriptRoot)

  if (Get-Command Get-VanGovernanceConfig -ErrorAction SilentlyContinue) {
    return
  }

  $dir = $CallingScriptRoot
  for ($i = 0; $i -lt 6; $i++) {
    $inVan2Scripts = Join-Path $dir 'deploy-governance.ps1'
    if (Test-Path $inVan2Scripts) {
      . $inVan2Scripts
      return
    }

    $viaVan2 = Join-Path $dir 'van2\scripts\deploy-governance.ps1'
    if (Test-Path $viaVan2) {
      . $viaVan2
      return
    }

    $parent = Split-Path $dir -Parent
    if (-not $parent -or $parent -eq $dir) {
      break
    }
    $dir = $parent
  }

  throw 'deploy-governance.ps1 not found. Expected under Desktop\van2\scripts\'
}

function Get-VanGovernanceRoot {
  $scriptsRoot = Split-Path -Parent $MyInvocation.ScriptName
  $van2Root = Split-Path -Parent $scriptsRoot
  $desktopRoot = Split-Path -Parent $van2Root

  [ordered]@{
    DesktopRoot      = $desktopRoot
    Van1Root         = Join-Path $desktopRoot 'van1\my-flutter'
    Van2Root         = $van2Root
    Van3Root         = Join-Path $desktopRoot 'van3'
    Van4Root         = Join-Path $desktopRoot 'van4'
    GovernanceScript = Join-Path $scriptsRoot 'deploy-governance.ps1'
    CanonicalRules   = Join-Path $van2Root 'firestore.rules'
    SyncScript       = Join-Path $scriptsRoot 'sync-firestore-rules.ps1'
    PreflightScript  = Join-Path $scriptsRoot 'deploy-preflight.ps1'
    SafeDeployScript = Join-Path $scriptsRoot 'deploy-safe.ps1'
  }
}

function Get-VanGovernanceConfig {
  $paths = Get-VanGovernanceRoot

  [ordered]@{
    ProjectId              = 'van-merchant'
    FinalAcknowledge       = 'YES I UNDERSTAND'
    FirestoreDatabaseId    = '(default)'
    FirestoreCanonicalApp  = 'van2'
    FirestoreSharedImpact  = 'SHARED:van1,van2,van3,van4'
    FirestoreCanonicalFile = 'firestore.rules'
    FirestoreSyncTargets   = @(
      @{ App = 'van1'; Path = (Join-Path $paths.Van1Root 'firestore.rules') }
      @{ App = 'van3'; Path = (Join-Path $paths.Van3Root 'firestore.rules') }
    )
    FunctionCodebases        = @{
      van1 = 'van1'
      van2 = 'van2'
    }
    FunctionOwnershipVan1  = @(
      'verifyTopUpSlip',
      'computeRouteMetrics',
      'checkPreparingOrders',
      'onOrderStatusUpdate',
      'calculateDeliveryTime',
      'askGeminiFlash',
      'analyzeProductWithAi',
      'onProductCatalogClassify',
      'replaceImageBackgroundWhite',
      'notifyNewChatMessage',
      'notifyLegacyChatMessage',
      'sendMonthlySalesReports'
    )
    FunctionOwnershipVan2  = @(
      'sendEmailOtp',
      'verifyEmailOtp',
      'sendMerchantPhoneOtp',
      'verifyMerchantPhoneOtp',
      'lookupLoginIdentifier',
      'upsertPhonePasswordProfile',
      'signInWithPhonePassword',
      'calculateCartTotals',
      'createCheckoutOrders',
      'createNationwideParcelOrders',
      'verifyOrderPaymentSlip',
      'normalizeVan2SlipOrders',
      'pushAppNotification',
      'sendAnnouncementEmails',
      'callUser',
      'initiateCall',
      'cancelCallInvite'
    )
    BlockedScriptNames     = @(
      'deploy-van-merchant-rules.ps1'
    )
    ForbiddenRawDeployOnly = @(
      'firestore:rules',
      'firestore',
      'functions',
      'storage'
    )
    Apps = [ordered]@{
      van1 = @{
        Label              = 'Merchant'
        Root               = $paths.Van1Root
        FunctionsCodebase  = 'van1'
        HostingTarget      = 'van1'
        StorageTarget      = 'van1'
        CanDeployFirestore = $false
        CanDeployFunctions = $true
        CanDeployStorage   = $true
        CanDeployHosting   = $true
      }
      van2 = @{
        Label              = 'Customer'
        Root               = $paths.Van2Root
        FunctionsCodebase  = 'van2'
        HostingTarget      = 'van2'
        StorageTarget      = 'van2'
        CanDeployFirestore = $true
        CanDeployFunctions = $true
        CanDeployStorage   = $true
        CanDeployHosting   = $true
      }
      van3 = @{
        Label              = 'Rider'
        Root               = $paths.Van3Root
        FunctionsCodebase  = $null
        HostingTarget      = 'van3'
        StorageTarget      = 'van3'
        CanDeployFirestore = $false
        CanDeployFunctions = $false
        CanDeployStorage   = $true
        CanDeployHosting   = $true
      }
      van4 = @{
        Label                     = 'Admin'
        Root                      = $paths.Van4Root
        FunctionsCodebase         = $null
        HostingTarget             = 'van4'
        StorageTarget             = 'van4'
        IsolatedFirestoreDatabase = 'van4'
        CanDeployFirestore        = $false
        CanDeployFunctions        = $false
        CanDeployStorage          = $true
        CanDeployHosting          = $true
        CanDeployIsolatedFirestore = $true
      }
    }
  }
}

function Get-VanDeployConfirmToken {
  param([Parameter(Mandatory)][ValidateSet('van1','van2','van3','van4')][string]$App)
  $cfg = Get-VanGovernanceConfig
  "APPROVE:${App}:$($cfg.ProjectId)"
}

function Assert-VanDeployConfirmation {
  param(
    [Parameter(Mandatory)][ValidateSet('van1','van2','van3','van4')][string]$App,
    [Parameter(Mandatory)][string]$ConfirmDeploy
  )
  $expected = Get-VanDeployConfirmToken -App $App
  if ($ConfirmDeploy -ne $expected) {
    throw "Deployment blocked. Re-run with: -ConfirmDeploy '$expected'"
  }
  Write-Host "[guard] Confirmation accepted: $expected" -ForegroundColor Green
}

function Assert-VanFinalAcknowledge {
  param([Parameter(Mandatory)][string]$FinalAcknowledge)
  $cfg = Get-VanGovernanceConfig
  if ($FinalAcknowledge -ne $cfg.FinalAcknowledge) {
    throw "Deployment blocked. Re-run with: -FinalAcknowledge '$($cfg.FinalAcknowledge)'"
  }
  Write-Host '[guard] Final acknowledgement accepted.' -ForegroundColor Green
}

function Assert-VanImpactConfirmation {
  param(
    [Parameter(Mandatory)][string]$ConfirmImpact,
    [Parameter(Mandatory)][string]$ExpectedImpact
  )
  if ($ConfirmImpact -ne $ExpectedImpact) {
    throw "Deployment blocked. Re-run with: -ConfirmImpact '$ExpectedImpact'"
  }
  Write-Host "[guard] Impact confirmation accepted: $ExpectedImpact" -ForegroundColor Green
}

function Assert-VanFileConfirmation {
  param(
    [Parameter(Mandatory)][string]$ConfirmFile,
    [Parameter(Mandatory)][string]$ExpectedFile
  )
  if ($ConfirmFile -ne $ExpectedFile) {
    throw "Deployment blocked. Re-run with: -ConfirmFile '$ExpectedFile'"
  }
  Write-Host "[guard] File confirmation accepted: $ExpectedFile" -ForegroundColor Green
}

function Get-VanFirestoreRulesHash {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    throw "Missing Firestore rules file: $Path"
  }
  return (Get-FileHash $Path -Algorithm SHA256).Hash
}

function Sync-VanFirestoreRules {
  param([switch]$WhatIf)

  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot
  $canonical = $paths.CanonicalRules

  if (-not (Test-Path $canonical)) {
    throw "Canonical Firestore rules not found: $canonical"
  }

  $canonicalHash = Get-VanFirestoreRulesHash -Path $canonical
  Write-Host "[sync] Canonical ($($cfg.FirestoreCanonicalApp)): $canonicalHash" -ForegroundColor Cyan

  foreach ($target in $cfg.FirestoreSyncTargets) {
    $targetPath = $target.Path
    $targetDir = Split-Path -Parent $targetPath
    if (-not (Test-Path $targetDir)) {
      throw "Target app folder missing for $($target.App): $targetDir"
    }

    if ($WhatIf) {
      Write-Host "[sync][what-if] Would copy canonical rules -> $($target.App) ($targetPath)" -ForegroundColor Yellow
      continue
    }

    Copy-Item -Path $canonical -Destination $targetPath -Force
    $targetHash = Get-VanFirestoreRulesHash -Path $targetPath
    if ($targetHash -ne $canonicalHash) {
      throw "Sync failed for $($target.App): hash mismatch after copy."
    }
    Write-Host "[sync] $($target.App) synced OK" -ForegroundColor Green
  }
}

function Assert-VanFirestoreRulesSynced {
  param(
    [Parameter(Mandatory)][ValidateSet('van1','van2','van3','van4')][string]$App,
    [switch]$AutoSync
  )

  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot
  $canonical = $paths.CanonicalRules
  $canonicalHash = Get-VanFirestoreRulesHash -Path $canonical

  if ($App -eq $cfg.FirestoreCanonicalApp) {
    Write-Host "[guard] Deploying from canonical owner ($App)." -ForegroundColor Green
    return
  }

  $localRules = Join-Path $cfg.Apps[$App].Root 'firestore.rules'
  if (-not (Test-Path $localRules)) {
    if ($AutoSync) {
      Sync-VanFirestoreRules
      return
    }
    throw "Missing local rules for $App. Run: van2\scripts\sync-firestore-rules.ps1"
  }

  $localHash = Get-VanFirestoreRulesHash -Path $localRules
  if ($localHash -eq $canonicalHash) {
    Write-Host "[guard] $App rules match canonical." -ForegroundColor Green
    return
  }

  if ($AutoSync) {
    Write-Host "[guard] $App rules differ — auto-sync from canonical..." -ForegroundColor Yellow
    Sync-VanFirestoreRules
    return
  }

  throw @"
[guard] $App firestore.rules differs from canonical (van2).
  Local : $localHash
  Canon : $canonicalHash
Fix: edit ONLY van2/firestore.rules, then run:
  van2\scripts\sync-firestore-rules.ps1
Never deploy Firestore rules from van1/van3 directly without syncing.
"@
}

function Assert-VanFunctionOwnership {
  param(
    [Parameter(Mandatory)][ValidateSet('van1','van2')][string]$App,
    [Parameter(Mandatory)][string[]]$FunctionName
  )

  $cfg = Get-VanGovernanceConfig
  $foreignApp = if ($App -eq 'van1') { 'van2' } else { 'van1' }
  $foreignOwned = if ($App -eq 'van1') { $cfg.FunctionOwnershipVan2 } else { $cfg.FunctionOwnershipVan1 }
  $foreignRoot = $cfg.Apps[$foreignApp].Root

  foreach ($name in $FunctionName) {
    $clean = [string]$name
    $clean = $clean.Trim()
    if (-not $clean) { continue }
    if ($clean -notmatch '^[A-Za-z0-9_-]+$') {
      throw "Invalid function name '$clean'."
    }
    if ($foreignOwned -contains $clean) {
      throw "Deployment blocked. '$clean' is owned by $foreignApp. Deploy from $foreignRoot\scripts\deploy-functions-isolated.ps1"
    }
  }
}

function Assert-VanAppCanDeploy {
  param(
    [Parameter(Mandatory)][ValidateSet('van1','van2','van3','van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('firestore','functions','storage','hosting')][string]$Target
  )

  $cfg = Get-VanGovernanceConfig
  $appCfg = $cfg.Apps[$App]
  $prop = switch ($Target) {
    'firestore' { 'CanDeployFirestore' }
    'functions' { 'CanDeployFunctions' }
    'storage'   { 'CanDeployStorage' }
    'hosting'   { 'CanDeployHosting' }
  }

  if (-not $appCfg.Contains($prop) -or -not $appCfg[$prop]) {
    if ($Target -eq 'firestore') {
      throw "$App must NOT deploy Firestore rules directly. Edit van2/firestore.rules, sync, then deploy from van2/scripts/deploy-firestore-isolated.ps1"
    }
    if ($Target -eq 'functions') {
      throw "$App has no Cloud Functions codebase. Deploy functions only from van1 or van2 using deploy-functions-isolated.ps1"
    }
    throw "$App is not allowed to deploy $Target via isolated scripts. Check deploy-governance.ps1 Apps config."
  }
}

function Invoke-VanDeployPreflight {
  param(
    [Parameter(Mandatory)][ValidateSet('van1','van2','van3','van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('firestore','functions','storage','hosting','sync-rules')][string]$Target
  )

  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot
  $appRoot = $cfg.Apps[$App].Root

  if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    throw 'Firebase CLI was not found in PATH.'
  }

  if (-not (Test-Path $appRoot)) {
    throw "App root not found: $appRoot"
  }

  $firebaserc = Join-Path $appRoot '.firebaserc'
  if (-not (Test-Path $firebaserc)) {
    throw "Missing .firebaserc in $appRoot"
  }

  $rc = Get-Content $firebaserc -Raw | ConvertFrom-Json
  if ($rc.projects.default -ne $cfg.ProjectId) {
    throw "Project mismatch in $App .firebaserc (expected $($cfg.ProjectId))."
  }

  if ($Target -eq 'sync-rules') {
    Assert-VanFirestoreRulesSynced -App 'van2'
    return
  }

  if ($Target -eq 'firestore') {
    Assert-VanAppCanDeploy -App $App -Target 'firestore'
    Assert-VanFirestoreRulesSynced -App $App
    if (-not (Test-Path $paths.CanonicalRules)) {
      throw "Canonical rules missing: $($paths.CanonicalRules)"
    }
    return
  }

  if ($Target -eq 'functions') {
    Assert-VanAppCanDeploy -App $App -Target 'functions'
    $firebaseJson = Join-Path $appRoot 'firebase.json'
    if (-not (Test-Path $firebaseJson)) {
      throw "Missing firebase.json in $appRoot"
    }
    return
  }

  if ($Target -in @('storage', 'hosting')) {
    Assert-VanAppCanDeploy -App $App -Target $Target
    return
  }

  Write-Host "[preflight] $App / $Target OK (project $($cfg.ProjectId))" -ForegroundColor Green
}

function Get-VanJavaMajorVersion {
  param([string]$JavaExe = 'java')

  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = @(& $JavaExe -version 2>&1)
  }
  finally {
    $ErrorActionPreference = $previousEap
  }

  if (-not $output -or $output.Count -eq 0) {
    return 0
  }

  $text = $output[0].ToString()
  if ($text -match 'version "(\d+)') {
    return [int]$Matches[1]
  }
  return 0
}

function Test-VanJava21Ready {
  if ((Get-VanJavaMajorVersion) -ge 21) {
    return $true
  }

  if ($env:JAVA_HOME) {
    $fromHome = Join-Path $env:JAVA_HOME 'bin\java.exe'
    if ((Test-Path $fromHome) -and (Get-VanJavaMajorVersion -JavaExe $fromHome) -ge 21) {
      return $true
    }
  }

  $knownPatterns = @(
    'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    'C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe'
    'C:\Program Files\Microsoft\jdk-21*\bin\java.exe'
    'C:\Program Files\Java\jdk-21*\bin\java.exe'
  )
  foreach ($pattern in $knownPatterns) {
    Get-Item $pattern -ErrorAction SilentlyContinue | ForEach-Object {
      if ((Get-VanJavaMajorVersion -JavaExe $_.FullName) -ge 21) {
        return $true
      }
    }
  }

  return $false
}

function Invoke-VanDeployReadiness {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [string]$Target = 'storage',
    [switch]$Quiet
  )

  $targetFirestoreVan4 = 'firestore' + '-van4'
  $targetSyncRules = 'sync' + '-rules'
  $allowedTargets = @(
    'storage'
    'hosting'
    'functions'
    'firestore'
    $targetFirestoreVan4
    $targetSyncRules
  )
  $impactSummaryTargets = @(
    'storage'
    'hosting'
    'functions'
    'firestore'
    $targetFirestoreVan4
  )

  if ($Target -notin $allowedTargets) {
    throw "Invalid -Target '$Target'. Allowed: $($allowedTargets -join ', ')"
  }

  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot
  $failures = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()

  function Write-ReadinessCheck {
    param(
      [string]$Label,
      [bool]$Ok,
      [string]$Hint = ''
    )

    if (-not $Quiet) {
      $status = if ($Ok) { 'OK' } else { 'FAIL' }
      $color = if ($Ok) { 'Green' } else { 'Red' }
      $line = '  [' + $status + '] ' + $Label
      Write-Host $line -ForegroundColor $color
      if (-not $Ok -and $Hint) {
        Write-Host ('       ' + $Hint) -ForegroundColor DarkYellow
      }
    }

    if (-not $Ok) {
      $entry = $Label + ' - ' + $Hint
      $null = $failures.Add($entry)
    }
  }

  if (-not $Quiet) {
    Write-Host ''
    Write-Host ('=== Deploy Readiness: ' + $App + ' / ' + $Target + ' ===') -ForegroundColor Cyan
    Write-Host 'Docs: van2\scripts\DEPLOY_GOVERNANCE.md + DEPLOY_RISK_MATRIX.md' -ForegroundColor DarkGray
    Write-Host ''
  }

  if ($Target -in $impactSummaryTargets -and -not $Quiet) {
    Show-VanDeployImpactSummary -App $App -Target $Target
  }

  Write-ReadinessCheck -Label 'Firebase CLI in PATH' -Ok ([bool](Get-Command firebase -ErrorAction SilentlyContinue)) -Hint 'Install: npm i -g firebase-tools'
  Write-ReadinessCheck -Label ('App root exists (' + $App + ')') -Ok (Test-Path $cfg.Apps[$App].Root)

  $firebaserc = Join-Path $cfg.Apps[$App].Root '.firebaserc'
  Write-ReadinessCheck -Label '.firebaserc present' -Ok (Test-Path $firebaserc)
  if (Test-Path $firebaserc) {
    $rc = Get-Content $firebaserc -Raw | ConvertFrom-Json
    $projectOk = $rc.projects.default -eq $cfg.ProjectId
    $projectHint = 'Expected project ' + $cfg.ProjectId
    Write-ReadinessCheck -Label 'Project = van-merchant' -Ok $projectOk -Hint $projectHint
  }

  if ($Target -eq 'firestore') {
    Write-ReadinessCheck -Label 'Deploying from van2 (canonical)' -Ok ($App -eq 'van2') -Hint 'Firestore default DB is SHARED - deploy from van2 only'
    if (Test-Path $paths.CanonicalRules) {
      try {
        Assert-VanFirestoreRulesSynced -App 'van2'
        Write-ReadinessCheck -Label 'Canonical rules synced to van1/van3' -Ok $true
      }
      catch {
        Write-ReadinessCheck -Label 'Canonical rules synced to van1/van3' -Ok $false -Hint 'Run: van2\scripts\sync-firestore-rules.ps1'
      }
    }

    $javaOk = Test-VanJava21Ready
    Write-ReadinessCheck -Label 'Java 21+ for emulator pre-deploy gate' -Ok $javaOk -Hint 'Install JDK 21+ or set JAVA_HOME to Android Studio JBR'
    Write-ReadinessCheck -Label 'Node.js in PATH (smoke test)' -Ok ([bool](Get-Command node -ErrorAction SilentlyContinue)) -Hint 'Install Node 20+'
  }

  if ($Target -in @('firestore', 'functions')) {
    $null = $warnings.Add('SHARED or critical target - run van3 rider smoke test immediately after deploy')
  }

  if ($App -eq 'van3' -and $Target -eq 'firestore') {
    Write-ReadinessCheck -Label 'van3 blocked from Firestore deploy' -Ok $false -Hint 'Use van2 deploy-self -Target firestore'
  }

  if ($App -in @('van3', 'van4') -and $Target -eq 'functions') {
    Write-ReadinessCheck -Label ($App + ' has no functions codebase') -Ok $false -Hint 'Deploy functions from van1 or van2 only'
  }

  if (-not $Quiet -and $warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($w in $warnings) {
      Write-Host ('  ! ' + $w) -ForegroundColor Yellow
    }
  }

  if (-not $Quiet) {
    Write-Host ''
    Write-Host 'Allowed targets for this app:' -ForegroundColor DarkCyan
    $appCfg = $cfg.Apps[$App]
    $allowed = @()
    if ($appCfg.CanDeployStorage) { $allowed += 'storage' }
    if ($appCfg.CanDeployHosting) { $allowed += 'hosting' }
    if ($appCfg.CanDeployFunctions) { $allowed += 'functions' }
    if ($appCfg.CanDeployFirestore) { $allowed += 'firestore' }
    if ($appCfg.CanDeployIsolatedFirestore) { $allowed += $targetFirestoreVan4 }
    Write-Host ('  ' + ($allowed -join ', ')) -ForegroundColor Gray
    Write-Host ''
  }

  if ($failures.Count -gt 0) {
    if (-not $Quiet) {
      $failMsg = 'READINESS FAILED: ' + $failures.Count + ' issue(s)'
      Write-Host $failMsg -ForegroundColor Red
    }
    return 1
  }

  if (-not $Quiet) {
    Write-Host 'READINESS OK - use deploy-self.ps1 for isolated deploy' -ForegroundColor Green
    Write-Host ''
  }
  return 0
}

function Invoke-VanDeployGuardSession {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][string]$ConfirmDeploy,
    [Parameter(Mandatory)][string]$ConfirmFile,
    [Parameter(Mandatory)][string]$ExpectedFile,
    [Parameter(Mandatory)][string]$ConfirmImpact,
    [Parameter(Mandatory)][string]$ExpectedImpact,
    [string]$FinalAcknowledge,
    [switch]$InteractiveConfirm
  )

  $cfg = Get-VanGovernanceConfig
  Assert-VanDeployConfirmation -App $App -ConfirmDeploy $ConfirmDeploy
  Assert-VanFileConfirmation -ConfirmFile $ConfirmFile -ExpectedFile $ExpectedFile
  Assert-VanImpactConfirmation -ConfirmImpact $ConfirmImpact -ExpectedImpact $ExpectedImpact

  if ($InteractiveConfirm) {
    $interactiveFile = Read-Host "Interactive confirm file scope (expected: $ExpectedFile)"
    if ($interactiveFile -ne $ExpectedFile) {
      throw 'Interactive confirmation failed for file scope.'
    }
    $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $ExpectedImpact)"
    if ($interactiveImpact -ne $ExpectedImpact) {
      throw 'Interactive confirmation failed for impact scope.'
    }
    Write-Host '[interactive] File and impact confirmations accepted.' -ForegroundColor Green
    $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: $($cfg.FinalAcknowledge))"
  }

  Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge
}

function Invoke-VanStorageRulesDeploy {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][string]$ConfirmDeploy,
    [Parameter(Mandatory)][string]$ConfirmFile,
    [Parameter(Mandatory)][string]$ConfirmImpact,
    [string]$FinalAcknowledge,
    [switch]$InteractiveConfirm,
  [switch]$DryRun
)

  $cfg = Get-VanGovernanceConfig
  $appCfg = $cfg.Apps[$App]
  $appRoot = $appCfg.Root
  $rulesFile = 'storage.rules'
  $storageTarget = $appCfg.StorageTarget

  if (-not $storageTarget) {
    throw "$App has no storage target configured."
  }

  Set-Location $appRoot
  Invoke-VanDeployGuardSession `
    -App $App `
    -ConfirmDeploy $ConfirmDeploy `
    -ConfirmFile $ConfirmFile `
    -ExpectedFile $rulesFile `
    -ConfirmImpact $ConfirmImpact `
    -ExpectedImpact "SELF:$App" `
    -FinalAcknowledge $FinalAcknowledge `
    -InteractiveConfirm:$InteractiveConfirm

  Invoke-VanDeployPreflight -App $App -Target 'storage'

  if (-not (Test-Path $rulesFile)) {
    throw "Missing rules file: $rulesFile"
  }

  $rc = Get-Content (Join-Path $appRoot '.firebaserc') -Raw | ConvertFrom-Json
  $mappedBuckets = $rc.targets.$($cfg.ProjectId).storage.$storageTarget
  if (-not $mappedBuckets -or $mappedBuckets.Count -eq 0) {
    throw "Storage target '$storageTarget' is not mapped. Run: firebase target:apply storage $storageTarget <BUCKET> --project $($cfg.ProjectId)"
  }

  $tempConfig = ".firebase.storage.$App.tmp.json"
  @{
    storage = @(
      @{
        target = $storageTarget
        rules  = $rulesFile
      }
    )
  } | ConvertTo-Json -Depth 6 | Set-Content -Path $tempConfig -Encoding UTF8

  try {
    Write-Host "Deploying Storage rules to target '$storageTarget' (SELF:$App)" -ForegroundColor Cyan
    if ($DryRun) {
      Write-Host "[dry-run] Skipping firebase deploy for storage:$storageTarget" -ForegroundColor Yellow
      return
    }
    firebase deploy --project $cfg.ProjectId --only "storage:$storageTarget" --config $tempConfig
  }
  finally {
    if (Test-Path $tempConfig) {
      Remove-Item $tempConfig -Force
    }
  }
}

function Get-VanDeployImpactInfo {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')][string]$Target
  )

  switch ($Target) {
    'firestore' {
      return [ordered]@{
        Scope        = 'SHARED'
        Risk         = 'HIGH'
        AffectedApps = @('van1', 'van2', 'van3', 'van4')
        Summary      = 'Firestore rules on default DB (all apps share one database)'
        RiderRisk    = 'van3 orders/riders listeners fail if rules are wrong'
      }
    }
    'functions' {
      $riderNote = if ($App -eq 'van2') {
        'pushAppNotification affects rider job push'
      } else {
        'order/status functions affect shop flow'
      }
      return [ordered]@{
        Scope        = 'SELF'
        Risk         = 'MEDIUM'
        AffectedApps = @($App)
        Summary      = "Cloud Functions codebase $App"
        RiderRisk    = $riderNote
      }
    }
    'firestore-van4' {
      return [ordered]@{
        Scope        = 'SELF'
        Risk         = 'LOW'
        AffectedApps = @('van4')
        Summary      = 'Firestore DB van4 isolated (admin only)'
        RiderRisk    = 'Does not affect rider app'
      }
    }
    default {
      return [ordered]@{
        Scope        = 'SELF'
        Risk         = 'LOW'
        AffectedApps = @($App)
        Summary      = "$Target target for $App only"
        RiderRisk    = 'Does not affect rider Firestore listeners'
      }
    }
  }
}

function Show-VanDeployImpactSummary {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')][string]$Target
  )

  $info = Get-VanDeployImpactInfo -App $App -Target $Target
  Write-Host ''
  Write-Host '=== Deploy Impact (step 1) ===' -ForegroundColor Cyan
  Write-Host ("  App/Target : {0} / {1}" -f $App, $Target)
  Write-Host ("  Scope      : {0}" -f $info.Scope) -ForegroundColor $(if ($info.Scope -eq 'SHARED') { 'Red' } else { 'Green' })
  Write-Host ("  Risk       : {0}" -f $info.Risk)
  Write-Host ("  Affects    : {0}" -f ($info.AffectedApps -join ', '))
  Write-Host ("  Detail     : {0}" -f $info.Summary)
  Write-Host ("  Rider note : {0}" -f $info.RiderRisk) -ForegroundColor DarkYellow
  if ($info.Scope -eq 'SHARED') {
    Write-Host '  >> Auto backup rules before deploy (step 6)' -ForegroundColor Yellow
  }
  Write-Host ''
}

function Backup-VanFirestoreRules {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$Label,
    [switch]$DryRun
  )

  if (-not (Test-Path $SourcePath)) {
    throw "Cannot backup - missing rules file: $SourcePath"
  }

  $paths = Get-VanGovernanceRoot
  $backupDir = Join-Path $paths.Van2Root 'scripts\deploy-backups'
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $hash = (Get-FileHash $SourcePath -Algorithm SHA256).Hash
  $shortHash = $hash.Substring(0, 12)
  $backupFileName = "${Label}-${stamp}-${shortHash}.rules"
  $backupPath = Join-Path $backupDir $backupFileName

  if ($DryRun) {
    Write-Host "(backup) dry-run would save: $backupPath" -ForegroundColor Yellow
    return $backupPath
  }

  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  Copy-Item -Path $SourcePath -Destination $backupPath -Force

  $latestManifest = Join-Path $backupDir 'LATEST.txt'
  @(
    "timestamp=$stamp"
    "label=$Label"
    "file=$backupFileName"
    "sha256=$hash"
    "source=$SourcePath"
  ) | Set-Content -Path $latestManifest -Encoding UTF8

  Write-Host "(backup) Rules saved step 6: $backupPath" -ForegroundColor Green
  return $backupPath
}

function Show-VanPostDeployConnectionGuide {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')][string]$Target,
    [string]$BackupPath
  )

  $info = Get-VanDeployImpactInfo -App $App -Target $Target
  Write-Host ''
  Write-Host '=== After deploy - connection signals (step 4) ===' -ForegroundColor Cyan
  Write-Host 'Docs: van2\scripts\DEPLOY_CONNECTION_SIGNALS.md'
  Write-Host ''

  if ($info.Scope -eq 'SHARED' -or $Target -eq 'functions') {
    Write-Host 'Automated smoke test (step 3) runs after deploy via deploy-smoke-test.ps1'
    Write-Host 'Manual checks (optional):' -ForegroundColor Yellow
    Write-Host '  [ ] van3: Rider jobs page loads (no permission-denied)'
    Write-Host '  [ ] van3: online toggle updates riders doc'
    Write-Host '  [ ] van2: cart/order status loads'
    Write-Host '  [ ] van1: shop orders load'
    Write-Host ''
  }

  Write-Host 'Connection loss signals:' -ForegroundColor DarkYellow
  Write-Host '  permission-denied  -> Firestore rules issue / rollback'
  Write-Host '  endless spinner    -> listener error or network'
  Write-Host '  stale data         -> realtime listener dropped'
  Write-Host ''

  if ($BackupPath) {
    Write-Host "Rollback: van2\scripts\deploy-restore-firestore-rules.ps1 -BackupFile `"$BackupPath`""
  }
  Write-Host ''
}

function Show-VanDeployGovernanceHelp {
  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot

  Write-Host ''
  Write-Host '=== Van Ecosystem Safe Deploy ===' -ForegroundColor Cyan
  Write-Host "Project: $($cfg.ProjectId)"
  Write-Host "Firestore canonical: $($paths.CanonicalRules)"
  Write-Host ''
  Write-Host 'RULE 1 — Firestore rules: edit van2 only, sync, deploy from van2' -ForegroundColor Yellow
  Write-Host '  sync:  van2\scripts\sync-firestore-rules.ps1'
  Write-Host '  deploy: van2\scripts\deploy-firestore-isolated.ps1 -ConfirmDeploy APPROVE:van2:van-merchant ...'
  Write-Host ''
  Write-Host 'RULE 2 — Functions: one codebase per function, never cross-deploy' -ForegroundColor Yellow
  Write-Host ("  van1: {0}" -f ($cfg.FunctionOwnershipVan1 -join ', '))
  Write-Host ("  van2: {0}" -f ($cfg.FunctionOwnershipVan2 -join ', '))
  Write-Host ''
  Write-Host 'RULE 3 — Never use deploy-van-merchant-rules.ps1 or raw firebase deploy for shared resources' -ForegroundColor Yellow
  Write-Host ''
  Write-Host 'RULE 4 — Always pass ConfirmDeploy, ConfirmFile, ConfirmImpact, FinalAcknowledge' -ForegroundColor Yellow
  Write-Host ''
  Write-Host 'Per-app entry (from any repo):' -ForegroundColor Green
  Write-Host '  ALL APPS: van2\scripts\deploy-readiness.ps1 then deploy-self.ps1 -App <vanN> -Target <one>'
  Write-Host '  van1: deploy-self -App van1 -Target storage|hosting|functions'
  Write-Host '  van2: deploy-self -App van2 -Target firestore|storage|hosting|functions'
  Write-Host '  van3: deploy-self -App van3 -Target storage|hosting ONLY'
  Write-Host '  van4: deploy-self -App van4 -Target storage|hosting|firestore-van4'
  Write-Host ''
  Write-Host 'Risk matrix: van2\scripts\DEPLOY_RISK_MATRIX.md' -ForegroundColor Yellow
  Write-Host 'Global help: van2\scripts\deploy-safe.ps1 -Action help' -ForegroundColor Green
  Write-Host ''
}
