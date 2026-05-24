param(
  [string[]]$FunctionName,
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance-import.ps1') -CallingScriptRoot $PSScriptRoot
$deployScript = Join-Path $PSScriptRoot 'deploy-isolated.ps1'

if (-not $FunctionName -or $FunctionName.Count -eq 0) {
  throw 'Functions deploy is locked to explicit function names.'
}
if (-not (Test-Path $deployScript)) {
  throw "Missing deploy script: $deployScript"
}

Assert-VanFunctionOwnership -App 'van2' -FunctionName $FunctionName
Invoke-VanDeployGuardSession -App 'van2' -ConfirmDeploy $ConfirmDeploy -ConfirmFile $ConfirmFile -ExpectedFile 'functions' -ConfirmImpact $ConfirmImpact -ExpectedImpact 'SELF:van2' -FinalAcknowledge $FinalAcknowledge -InteractiveConfirm:$InteractiveConfirm
Invoke-VanDeployPreflight -App 'van2' -Target 'functions'

& $deployScript -FunctionsOnly -FunctionName $FunctionName -ConfirmDeploy $ConfirmDeploy -ConfirmFile $ConfirmFile -ConfirmImpact $ConfirmImpact -FinalAcknowledge $FinalAcknowledge -DryRun:$DryRun
