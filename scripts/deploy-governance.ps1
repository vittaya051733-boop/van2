# Single source of truth for van1–van4 deploy policy on project van-merchant.
# Dot-source: Import-VanDeployGovernance -CallingScriptRoot $PSScriptRoot

$ErrorActionPreference = 'Stop'

$VanDeployLocaleScript = Join-Path $PSScriptRoot 'deploy-locale-th.ps1'
$script:VanDeployScriptsRoot = $PSScriptRoot
if (Test-Path $VanDeployLocaleScript) {
  . $VanDeployLocaleScript
}

try {
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [Console]::OutputEncoding = $utf8NoBom
  $OutputEncoding = $utf8NoBom
}
catch {}

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
    FinalAcknowledge       = (Get-VanAckEn)
    FinalAcknowledgeTh     = (Get-VanAckTh)
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
      'onOrderStatusUpdate',
      'calculateDeliveryTime',
      'askGeminiFlash',
      'analyzeProductWithAi',
      'enqueueProductAiAnalysis',
      'onProductAiJobQueued',
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
      'createTravelOrder',
      'quoteTravelFare',
      'createNationwideParcelOrders',
      'recordCheckoutDiscounts',
      'verifyOrderPaymentSlip',
      'normalizeVan2SlipOrders',
      'pushAppNotification',
      'sendAnnouncementEmails',
      'callUser',
      'initiateCall',
      'cancelCallInvite',
      'computeRouteMetrics',
      'placesAutocomplete',
      'placesResolvePlace',
      'reverseGeocodeDeliveryLocation',
      'syncVan2CartStockHold',
      'checkPreparingOrders',
      'getMerchantWallet',
      'adminCancelMerchantContract',
      'adminResolveClaim',
      'syncMerchantWalletOnCreditWrite',
      'syncMerchantWalletOnContractWrite'
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
  $expectedTh = ConvertTo-VanDeployTokenTh $expected
  if (-not (Test-VanDeployTokenMatch -Provided $ConfirmDeploy -ExpectedEn $expected)) {
    throw (Get-VanMsg 'blockedConfirmDeploy' @($expectedTh))
  }
  Write-Host (Get-VanMsg 'confirmDeployAccepted' @($expectedTh)) -ForegroundColor Green
}

function Assert-VanFinalAcknowledge {
  param([Parameter(Mandatory)][string]$FinalAcknowledge)
  $cfg = Get-VanGovernanceConfig
  if (-not (Test-VanAckMatch -Provided $FinalAcknowledge -ExpectedEn $cfg.FinalAcknowledge)) {
    throw (Get-VanMsg 'blockedFinalAck' @($cfg.FinalAcknowledgeTh))
  }
  Write-Host (Get-VanMsg 'confirmFinalAccepted') -ForegroundColor Green
}

function Assert-VanImpactConfirmation {
  param(
    [Parameter(Mandatory)][string]$ConfirmImpact,
    [Parameter(Mandatory)][string]$ExpectedImpact
  )
  $expectedTh = ConvertTo-VanImpactTokenTh $ExpectedImpact
  if (-not (Test-VanImpactTokenMatch -Provided $ConfirmImpact -ExpectedEn $ExpectedImpact)) {
    throw (Get-VanMsg 'blockedConfirmImpact' @($expectedTh))
  }
  Write-Host (Get-VanMsg 'confirmImpactAccepted' @($expectedTh)) -ForegroundColor Green
}

function Assert-VanFileConfirmation {
  param(
    [Parameter(Mandatory)][string]$ConfirmFile,
    [Parameter(Mandatory)][string]$ExpectedFile
  )
  if ($ConfirmFile -ne $ExpectedFile) {
    throw (Get-VanMsg 'blockedConfirmFile' @($ExpectedFile))
  }
  Write-Host (Get-VanMsg 'confirmFileAccepted' @($ExpectedFile)) -ForegroundColor Green
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
  Write-Host (Get-VanMsg 'syncCanonical' @($cfg.FirestoreCanonicalApp, $canonicalHash)) -ForegroundColor Cyan

  foreach ($target in $cfg.FirestoreSyncTargets) {
    $targetPath = $target.Path
    $targetDir = Split-Path -Parent $targetPath
    if (-not (Test-Path $targetDir)) {
      throw "Target app folder missing for $($target.App): $targetDir"
    }

    if ($WhatIf) {
      Write-Host (Get-VanMsg 'syncWhatIf' @($target.App, $targetPath)) -ForegroundColor Yellow
      continue
    }

    Copy-Item -Path $canonical -Destination $targetPath -Force
    $targetHash = Get-VanFirestoreRulesHash -Path $targetPath
    if ($targetHash -ne $canonicalHash) {
      throw "Sync failed for $($target.App): hash mismatch after copy."
    }
    Write-Host (Get-VanMsg 'syncOk' @($target.App)) -ForegroundColor Green
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
    Write-Host (Get-VanMsg 'guardCanonicalOwner' @($App)) -ForegroundColor Green
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
    Write-Host (Get-VanMsg 'guardRulesMatch' @($App)) -ForegroundColor Green
    return
  }

  if ($AutoSync) {
    Write-Host (Get-VanMsg 'guardRulesAutoSync' @($App)) -ForegroundColor Yellow
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
      $status = if ($Ok) { (Get-VanMsg 'readinessStatusOk') } else { (Get-VanMsg 'readinessStatusFail') }
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
    Write-Host (Get-VanMsg 'readinessTitle' @($App, $Target)) -ForegroundColor Cyan
    Write-Host (Get-VanMsg 'readinessDocs') -ForegroundColor DarkGray
    Write-Host ''
  }

  if ($Target -in $impactSummaryTargets -and -not $Quiet) {
    Show-VanDeployImpactSummary -App $App -Target $Target
  }

  Write-ReadinessCheck -Label (Get-VanMsg 'readinessFirebaseCli') -Ok ([bool](Get-Command firebase -ErrorAction SilentlyContinue)) -Hint (Get-VanMsg 'readinessFirebaseCliHint')
  Write-ReadinessCheck -Label (Get-VanMsg 'readinessAppRoot' @($App)) -Ok (Test-Path $cfg.Apps[$App].Root)

  $firebaserc = Join-Path $cfg.Apps[$App].Root '.firebaserc'
  Write-ReadinessCheck -Label (Get-VanMsg 'readinessFirebaserc') -Ok (Test-Path $firebaserc)
  if (Test-Path $firebaserc) {
    $rc = Get-Content $firebaserc -Raw | ConvertFrom-Json
    $projectOk = $rc.projects.default -eq $cfg.ProjectId
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessProject') -Ok $projectOk -Hint (Get-VanMsg 'readinessProjectHint' @($cfg.ProjectId))
  }

  if ($Target -eq 'firestore') {
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessVan2Canonical') -Ok ($App -eq 'van2') -Hint (Get-VanMsg 'readinessVan2CanonicalHint')
    if (Test-Path $paths.CanonicalRules) {
      try {
        Assert-VanFirestoreRulesSynced -App 'van2'
        Write-ReadinessCheck -Label (Get-VanMsg 'readinessRulesSynced') -Ok $true
      }
      catch {
        Write-ReadinessCheck -Label (Get-VanMsg 'readinessRulesSynced') -Ok $false -Hint (Get-VanMsg 'readinessRulesSyncedHint')
      }
    }

    $javaOk = Test-VanJava21Ready
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessJava21') -Ok $javaOk -Hint (Get-VanMsg 'readinessJava21Hint')
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessNode') -Ok ([bool](Get-Command node -ErrorAction SilentlyContinue)) -Hint (Get-VanMsg 'readinessNodeHint')
  }

  if ($Target -in @('firestore', 'functions')) {
    $null = $warnings.Add((Get-VanMsg 'readinessWarnShared'))
  }

  if ($App -eq 'van3' -and $Target -eq 'firestore') {
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessVan3Blocked') -Ok $false -Hint (Get-VanMsg 'readinessVan3BlockedHint')
  }

  if ($App -in @('van3', 'van4') -and $Target -eq 'functions') {
    Write-ReadinessCheck -Label (Get-VanMsg 'readinessNoFunctions' @($App)) -Ok $false -Hint (Get-VanMsg 'readinessNoFunctionsHint')
  }

  if (-not $Quiet -and $warnings.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-VanMsg 'readinessWarnings') -ForegroundColor Yellow
    foreach ($w in $warnings) {
      Write-Host ('  ! ' + $w) -ForegroundColor Yellow
    }
  }

  if (-not $Quiet) {
    Write-Host ''
    Write-Host (Get-VanMsg 'readinessAllowedTargets') -ForegroundColor DarkCyan
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
      $failMsg = Get-VanMsg 'readinessFailed' @($failures.Count)
      Write-Host $failMsg -ForegroundColor Red
    }
    return 1
  }

  if (-not $Quiet) {
    Write-Host (Get-VanMsg 'readinessOk') -ForegroundColor Green
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
    $expectedImpactTh = ConvertTo-VanImpactTokenTh $ExpectedImpact
    $interactiveFile = Read-Host (Get-VanMsg 'interactiveFilePrompt' @($ExpectedFile))
    if ($interactiveFile -ne $ExpectedFile) {
      throw (Get-VanMsg 'interactiveFileFail')
    }
    $interactiveImpact = Read-Host (Get-VanMsg 'interactiveImpactPrompt' @($expectedImpactTh))
    if (-not (Test-VanImpactTokenMatch -Provided $interactiveImpact -ExpectedEn $ExpectedImpact)) {
      throw (Get-VanMsg 'interactiveImpactFail')
    }
    Write-Host (Get-VanMsg 'interactiveOk') -ForegroundColor Green
    $FinalAcknowledge = Read-Host (Get-VanMsg 'interactiveFinalPrompt' @($cfg.FinalAcknowledgeTh))
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
    Write-Host (Get-VanMsg 'storageDeploy' @($storageTarget, (Get-VanSelfImpactTh $App))) -ForegroundColor Cyan
    if ($DryRun) {
      Write-Host (Get-VanMsg 'storageDryRun' @($storageTarget)) -ForegroundColor Yellow
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
        ScopeTh      = (Get-VanMsg 'scopeSharedTh')
        Risk         = 'HIGH'
        RiskTh       = (Get-VanMsg 'riskHighTh')
        AffectedApps = @('van1', 'van2', 'van3', 'van4')
        Summary      = (Get-VanMsg 'impactFirestoreSummary')
        RiderRisk    = (Get-VanMsg 'impactFirestoreRider')
      }
    }
    'functions' {
      $riderNote = if ($App -eq 'van2') {
        (Get-VanMsg 'impactFunctionsVan2Rider')
      } else {
        (Get-VanMsg 'impactFunctionsVan1Rider')
      }
      return [ordered]@{
        Scope        = 'SELF'
        ScopeTh      = (Get-VanMsg 'scopeSelfTh')
        Risk         = 'MEDIUM'
        RiskTh       = (Get-VanMsg 'riskMediumTh')
        AffectedApps = @($App)
        Summary      = (Get-VanMsg 'impactFunctionsSummary' @($App))
        RiderRisk    = $riderNote
      }
    }
    'firestore-van4' {
      return [ordered]@{
        Scope        = 'SELF'
        ScopeTh      = (Get-VanMsg 'scopeSelfTh')
        Risk         = 'LOW'
        RiskTh       = (Get-VanMsg 'riskLowTh')
        AffectedApps = @('van4')
        Summary      = (Get-VanMsg 'impactFirestoreVan4Summary')
        RiderRisk    = (Get-VanMsg 'impactFirestoreVan4Rider')
      }
    }
    default {
      return [ordered]@{
        Scope        = 'SELF'
        ScopeTh      = (Get-VanMsg 'scopeSelfTh')
        Risk         = 'LOW'
        RiskTh       = (Get-VanMsg 'riskLowTh')
        AffectedApps = @($App)
        Summary      = (Get-VanMsg 'impactDefaultSummary' @($Target, $App))
        RiderRisk    = (Get-VanMsg 'impactDefaultRider')
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
  Write-Host (Get-VanMsg 'impactTitle') -ForegroundColor Cyan
  Write-Host (Get-VanMsg 'impactAppTarget' @($App, $Target))
  Write-Host (Get-VanMsg 'impactScope' @($info.ScopeTh)) -ForegroundColor $(if ($info.Scope -eq 'SHARED') { 'Red' } else { 'Green' })
  Write-Host (Get-VanMsg 'impactRisk' @($info.RiskTh))
  Write-Host (Get-VanMsg 'impactApps' @(($info.AffectedApps -join ', ')))
  Write-Host (Get-VanMsg 'impactDetail' @($info.Summary))
  Write-Host (Get-VanMsg 'impactRider' @($info.RiderRisk)) -ForegroundColor DarkYellow
  if ($info.Scope -eq 'SHARED' -or $Target -in @('firestore', 'firestore-van4', 'storage', 'functions', 'hosting')) {
    Write-Host (Get-VanMsg 'impactBackupNote') -ForegroundColor Yellow
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'impactConfirmHeader') -ForegroundColor DarkCyan
  Write-Host ("  -ConfirmDeploy `"$(ConvertTo-VanDeployTokenTh (Get-VanDeployConfirmToken -App $App))`"") -ForegroundColor Gray
  if ($Target -eq 'firestore') {
    Write-Host ("  -ConfirmImpact `"$(Get-VanSharedImpactTh)`"") -ForegroundColor Gray
    Write-Host '  -ConfirmFile "firestore.rules"' -ForegroundColor Gray
  } elseif ($Target -eq 'firestore-van4') {
    Write-Host ("  -ConfirmImpact `"$(Get-VanSelfImpactTh 'van4')`"") -ForegroundColor Gray
    Write-Host '  -ConfirmFile "firestore.rules"' -ForegroundColor Gray
  } else {
    Write-Host ("  -ConfirmImpact `"$(Get-VanSelfImpactTh $App)`"") -ForegroundColor Gray
  }
  Write-Host ("  -FinalAcknowledge `"$(Get-VanAckTh)`"") -ForegroundColor Gray
  Write-Host ''
}

. (Join-Path $PSScriptRoot 'deploy-backup.ps1')
. (Join-Path $PSScriptRoot 'deploy-ledger.ps1')

function Show-VanPostDeployConnectionGuide {
  param(
    [Parameter(Mandatory)][ValidateSet('van1', 'van2', 'van3', 'van4')][string]$App,
    [Parameter(Mandatory)][ValidateSet('storage', 'hosting', 'functions', 'firestore', 'firestore-van4')][string]$Target,
    [string]$BackupPath
  )

  $info = Get-VanDeployImpactInfo -App $App -Target $Target
  Write-Host ''
  Write-Host (Get-VanMsg 'postDeployTitle') -ForegroundColor Cyan
  Write-Host (Get-VanMsg 'postDeployDocs')
  Write-Host ''

  if ($info.Scope -eq 'SHARED' -or $Target -eq 'functions') {
    Write-Host (Get-VanMsg 'postDeploySmokeAuto')
    Write-Host (Get-VanMsg 'postDeployManual') -ForegroundColor Yellow
    Write-Host (Get-VanMsg 'postDeployCheckVan3Jobs')
    Write-Host (Get-VanMsg 'postDeployCheckVan3Online')
    Write-Host (Get-VanMsg 'postDeployCheckVan2Cart')
    Write-Host (Get-VanMsg 'postDeployCheckVan1Orders')
    Write-Host ''
  }

  Write-Host (Get-VanMsg 'postDeploySignals') -ForegroundColor DarkYellow
  Write-Host (Get-VanMsg 'postDeploySignalDenied')
  Write-Host (Get-VanMsg 'postDeploySignalSpinner')
  Write-Host (Get-VanMsg 'postDeploySignalStale')
  Write-Host ''

  if ($BackupPath) {
    Write-Host "Rollback: van2\scripts\deploy-restore-backup.ps1 -BackupDir `"$BackupPath`""
    Write-Host "Rollback (firestore shared): van2\scripts\deploy-restore-firestore-rules.ps1"
  }
  Write-Host ''
}

function Show-VanDeployGovernanceHelp {
  $cfg = Get-VanGovernanceConfig
  $paths = Get-VanGovernanceRoot

  Write-Host ''
  Write-Host (Get-VanMsg 'helpTitle') -ForegroundColor Cyan
  Write-Host (Get-VanMsg 'helpProject' @($cfg.ProjectId))
  Write-Host (Get-VanMsg 'helpCanonicalRules' @($paths.CanonicalRules))
  Write-Host ''
  Write-Host (Get-VanMsg 'helpRule1') -ForegroundColor Yellow
  Write-Host (Get-VanMsg 'helpRule1Sync')
  Write-Host (Get-VanMsg 'helpRule1Deploy')
  Write-Host ''
  Write-Host (Get-VanMsg 'helpRule2') -ForegroundColor Yellow
  Write-Host ("  van1: {0}" -f ($cfg.FunctionOwnershipVan1 -join ', '))
  Write-Host ("  van2: {0}" -f ($cfg.FunctionOwnershipVan2 -join ', '))
  Write-Host ''
  Write-Host (Get-VanMsg 'helpRule3') -ForegroundColor Yellow
  Write-Host ''
  Write-Host (Get-VanMsg 'helpRule4') -ForegroundColor Yellow
  Write-Host ''
  Write-Host (Get-VanMsg 'helpEntryPoints') -ForegroundColor Green
  Write-Host (Get-VanMsg 'helpAllApps')
  Write-Host (Get-VanMsg 'helpVan1')
  Write-Host (Get-VanMsg 'helpVan2')
  Write-Host (Get-VanMsg 'helpVan3')
  Write-Host (Get-VanMsg 'helpVan4')
  Write-Host ''
  Write-Host (Get-VanMsg 'helpRiskMatrix') -ForegroundColor Yellow
  Write-Host (Get-VanMsg 'helpSafeHelp') -ForegroundColor Green
  Write-Host ''
}
