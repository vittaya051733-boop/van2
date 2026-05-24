param(
  [string]$CallingScriptRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (Get-Command Get-VanGovernanceConfig -ErrorAction SilentlyContinue) {
  return
}

$dir = $CallingScriptRoot
for ($i = 0; $i -lt 6; $i++) {
  $direct = Join-Path $dir 'deploy-governance.ps1'
  if (Test-Path $direct) {
    . $direct
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

throw 'deploy-governance.ps1 not found. Install under Desktop\van2\scripts\'
