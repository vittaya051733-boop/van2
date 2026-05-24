param(
  [Parameter(Mandatory)]
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App,

  [Parameter(Mandatory)]
  [ValidateSet('firestore', 'functions', 'storage', 'hosting', 'sync-rules')]
  [string]$Target
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

Invoke-VanDeployPreflight -App $App -Target $Target
Write-Host "[preflight] PASS — $App / $Target" -ForegroundColor Green
