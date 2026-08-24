<#
.SYNOPSIS
  Deploy by named bundle (BUNDLE-xxx) - focused scope only.

.EXAMPLE
  .\deploy-bundle.ps1 -List
  .\deploy-bundle.ps1 -Bundle BUNDLE-A01 -ShowOnly
#>
param(
  [string]$Bundle,
  [switch]$List,
  [switch]$ShowOnly,
  [switch]$DryRunOnly,
  [switch]$Execute,
  [string]$ConfirmDeploy,
  [string]$ConfirmImpact,
  [string]$FinalAcknowledge,
  [switch]$InteractiveConfirm,
  [switch]$BuildWeb,
  [switch]$SkipPreDeploySmoke,
  [switch]$AllowSkipEmulatorSmoke
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'deploy-governance.ps1')
. (Join-Path $scriptRoot 'deploy-bundle-lib.ps1')

if ([string]::IsNullOrWhiteSpace($FinalAcknowledge)) {
  $FinalAcknowledge = Get-VanAckTh
}

if ($List) {
  Show-VanDeployBundleList
  exit 0
}

if (-not $Bundle) {
  Show-VanDeployBundleList
  exit 0
}

if (-not $ShowOnly -and -not $DryRunOnly -and -not $Execute) {
  Write-Host 'Choose: -ShowOnly | -DryRunOnly | -Execute' -ForegroundColor Yellow
  exit 1
}

$def = Resolve-VanDeployBundle -Bundle $Bundle
Show-VanDeployBundleImpactTh -BundleDef $def

$firebaseSteps = @($def.firebaseSteps)
if ($firebaseSteps.Count -eq 0) {
  if ($Execute -or $DryRunOnly) {
    Write-Host 'No Firebase steps in this bundle - use buildSteps (APK/hot reload)' -ForegroundColor Yellow
  }
  exit 0
}

if ($ShowOnly) {
  Write-Host 'Firebase steps present - run -DryRunOnly or -Execute when ready' -ForegroundColor Cyan
  exit 0
}

$batchScript = Join-Path $scriptRoot 'deploy-batch.ps1'
$batchArgs = @{
  Step                   = $firebaseSteps
  FinalAcknowledge       = $FinalAcknowledge
  InteractiveConfirm     = $InteractiveConfirm
  BuildWeb               = $BuildWeb
  SkipPreDeploySmoke     = $SkipPreDeploySmoke
  AllowSkipEmulatorSmoke = $AllowSkipEmulatorSmoke
}

if ($ConfirmDeploy) { $batchArgs.ConfirmDeploy = $ConfirmDeploy }
if ($ConfirmImpact) {
  $batchArgs.ConfirmImpact = $ConfirmImpact
}
elseif ($def.confirmImpact) {
  $batchArgs.ConfirmImpact = $def.confirmImpact
}

if ($DryRunOnly) {
  & $batchScript @batchArgs -DryRunOnly
  exit $LASTEXITCODE
}

& $batchScript @batchArgs -Execute
$code = $LASTEXITCODE
$status = if ($code -eq 0) { 'ok' } else { 'fail' }
if (Get-Command Write-VanDeployLedgerEntry -ErrorAction SilentlyContinue) {
  Write-VanDeployLedgerEntry -Kind 'bundle-execute' -Bundle $def.id -Status $status
}
exit $code
