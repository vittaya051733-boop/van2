<#
.SYNOPSIS
  Pre-deploy checklist - run before ANY Firebase deploy in van ecosystem.
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet('van1', 'van2', 'van3', 'van4')]
  [string]$App,

  [string]$Target = 'storage',

  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deploy-governance.ps1')

$exitCode = Invoke-VanDeployReadiness -App $App -Target $Target -Quiet:$Quiet
exit $exitCode
