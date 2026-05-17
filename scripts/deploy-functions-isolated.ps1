param(
  [string[]]$FunctionName
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployScript = Join-Path $scriptRoot 'deploy-isolated.ps1'

if (-not $FunctionName -or $FunctionName.Count -eq 0) {
  Write-Error 'Functions deploy is locked to explicit function names. Example: scripts/deploy-functions-isolated.ps1 -FunctionName verifyTopUpSlip'
  exit 1
}

if (-not (Test-Path $deployScript)) {
  Write-Error "Missing deploy script: $deployScript"
  exit 1
}

& powershell -ExecutionPolicy Bypass -File $deployScript -FunctionsOnly -FunctionName $FunctionName