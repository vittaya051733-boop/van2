<#
.SYNOPSIS
  Fast path: install existing Shorebird release on emulator (no full rebuild).
.EXAMPLE
  .\shorebird-preview-emulator.ps1
  .\shorebird-preview-emulator.ps1 -ReleaseVersion 1.0.1+2 -DeviceId emulator-5554
#>
param(
  [string]$DeviceId = 'emulator-5554',
  [string]$ReleaseVersion = '1.0.1+4',
  [string]$AppId = 'e85bf3aa-16ea-476d-b651-30f7fa386e5e'
)

$ErrorActionPreference = 'Stop'

$shorebird = Join-Path $env:USERPROFILE '.shorebird\bin\shorebird.bat'
if (-not (Test-Path $shorebird)) {
  throw 'Shorebird not installed. Run: iwr -useb https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1 | iex'
}

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (Test-Path $adb) {
  & $adb kill-server | Out-Null
  Start-Sleep -Seconds 1
  & $adb start-server | Out-Null
}

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

Write-Host "Shorebird preview $ReleaseVersion -> $DeviceId (downloads release, ~2-5 min, no Gradle build)" -ForegroundColor Cyan
& $shorebird preview --platform android -d $DeviceId --app-id $AppId --release-version $ReleaseVersion

if ($LASTEXITCODE -ne 0 -and (Test-Path $adb)) {
  Write-Host 'Preview start failed; trying to launch installed app...' -ForegroundColor Yellow
  & $adb -s $DeviceId shell am start -n Van2.com/van.merchant.MainActivity
}
