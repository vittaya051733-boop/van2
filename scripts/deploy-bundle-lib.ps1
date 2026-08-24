# Deploy bundle helpers

function Get-VanDeployBundlesRoot {
  Join-Path $script:VanDeployScriptsRoot 'deploy-bundles'
}

function Get-VanDeployBundleFiles {
  $root = Get-VanDeployBundlesRoot
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem -Path $root -Filter 'BUNDLE-*.json' -File | Sort-Object Name
}

function Resolve-VanDeployBundle {
  param([Parameter(Mandatory)][string]$Bundle)

  $token = $Bundle.Trim()
  $files = Get-VanDeployBundleFiles
  if ($files.Count -eq 0) {
    throw "No bundle files in $(Get-VanDeployBundlesRoot)"
  }

  foreach ($file in $files) {
    $raw = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($raw.id -eq $token -or $raw.slug -eq $token) {
      $raw | Add-Member -NotePropertyName '_file' -NotePropertyValue $file.FullName -Force
      return $raw
    }
  }

  foreach ($file in $files) {
    if ($file.BaseName -like "*$token*") {
      $raw = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      $raw | Add-Member -NotePropertyName '_file' -NotePropertyValue $file.FullName -Force
      return $raw
    }
  }

  throw "Bundle not found: '$Bundle'. Run deploy-bundle.ps1 -List"
}

function Show-VanDeployBundleList {
  $catalog = Join-Path (Get-VanDeployBundlesRoot) 'BUNDLE-CATALOG.th.md'
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleListTitle') -ForegroundColor Cyan
  if (Test-Path $catalog) {
    Write-Host (Get-VanMsg 'bundleCatalogPath' @($catalog)) -ForegroundColor Gray
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleListHeader') -ForegroundColor Yellow
  foreach ($file in (Get-VanDeployBundleFiles)) {
    $b = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $mode = if (@($b.firebaseSteps).Count -gt 0) { 'Firebase' } else { 'Build' }
    Write-Host ("  {0,-18} {1,-28} {2} ({3})" -f $b.id, $b.titleTh, $b.scope, $mode)
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleListHint') -ForegroundColor Green
  Write-Host ''
}

function Show-VanDeployBundleImpactTh {
  param([Parameter(Mandatory)]$BundleDef)

  Write-Host ''
  Write-Host (Get-VanMsg 'bundleImpactHeader') -ForegroundColor Cyan
  Write-Host (Get-VanMsg 'bundleImpactId' @($BundleDef.id))
  Write-Host (Get-VanMsg 'bundleImpactTitle' @($BundleDef.titleTh))
  Write-Host (Get-VanMsg 'bundleImpactProject' @($BundleDef.project))
  Write-Host (Get-VanMsg 'bundleImpactScope' @($BundleDef.scope))
  Write-Host (Get-VanMsg 'bundleImpactHeader') -ForegroundColor Cyan
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleSummaryLabel') -ForegroundColor Yellow
  Write-Host "  $($BundleDef.summaryTh)"
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleImpactLabel') -ForegroundColor Yellow
  foreach ($line in @($BundleDef.impactTh)) {
    Write-Host "  - $line"
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleRiskLabel' @($BundleDef.riskTh)) -ForegroundColor DarkYellow
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleWriterLabel' @(($BundleDef.writerApps -join ', ')))
  Write-Host (Get-VanMsg 'bundleConsumerLabel' @(($BundleDef.consumerApps -join ', ')))
  if ($BundleDef.collections) {
    Write-Host (Get-VanMsg 'bundleCollectionsLabel' @(($BundleDef.collections -join ', ')))
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleForbiddenLabel') -ForegroundColor Red
  foreach ($f in @($BundleDef.forbidden)) {
    Write-Host "  X $f"
  }
  Write-Host ''
  if ($BundleDef.allowedPaths -and @($BundleDef.allowedPaths).Count -gt 0) {
    Write-Host (Get-VanMsg 'bundleAllowedLabel') -ForegroundColor Green
    foreach ($p in @($BundleDef.allowedPaths)) {
      Write-Host "  + $p"
    }
    Write-Host ''
  }
  $steps = @($BundleDef.firebaseSteps)
  if ($steps.Count -gt 0) {
    Write-Host (Get-VanMsg 'bundleFirebaseStepsLabel') -ForegroundColor Cyan
    foreach ($s in $steps) { Write-Host "  -> $s" }
  }
  else {
    Write-Host (Get-VanMsg 'bundleNoFirebase') -ForegroundColor DarkYellow
  }
  Write-Host ''
  $builds = @($BundleDef.buildSteps)
  if ($builds.Count -gt 0) {
    Write-Host (Get-VanMsg 'bundleBuildStepsLabel') -ForegroundColor Cyan
    foreach ($b in $builds) {
      Write-Host ("  -> {0}: {1}" -f $b.app, $b.noteTh)
    }
    Write-Host ''
  }
  Write-Host (Get-VanMsg 'bundleSmokeLabel') -ForegroundColor Yellow
  foreach ($c in @($BundleDef.smokeChecklistTh)) {
    Write-Host "  [ ] $c"
  }
  Write-Host ''
  Write-Host (Get-VanMsg 'bundleAiRule1') -ForegroundColor Magenta
  Write-Host (Get-VanMsg 'bundleAiRule2') -ForegroundColor Magenta
  Write-Host ''
}
