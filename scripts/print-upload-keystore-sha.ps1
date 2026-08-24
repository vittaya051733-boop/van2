# Print upload keystore SHA-1/SHA-256 for Firebase App Check + Maps restrictions.
# Uses van2 android/key.properties by default (shared upload keystore for store builds).
param(
  [string]$KeyPropertiesPath = (Join-Path $PSScriptRoot '..\android\key.properties')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $KeyPropertiesPath)) {
  Write-Error "Missing $KeyPropertiesPath — copy android/key.properties.example first."
}

$props = @{}
Get-Content $KeyPropertiesPath | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') {
    $props[$matches[1].Trim()] = $matches[2].Trim()
  }
}

$storeFile = Join-Path (Split-Path $KeyPropertiesPath -Parent) $props.storeFile
if (-not (Test-Path $storeFile)) {
  Write-Error "Keystore not found: $storeFile"
}

Write-Host ''
Write-Host '=== Upload keystore fingerprints (App Check + Maps) ===' -ForegroundColor Cyan
keytool -list -v -keystore $storeFile -alias $props.keyAlias -storepass $props.storePassword | Select-String -Pattern 'SHA1:|SHA256:'
Write-Host ''
Write-Host 'Firebase Console → App Check → register SHA-256 for Van2.com / van.merchant' -ForegroundColor Yellow
Write-Host 'https://console.firebase.google.com/project/van-merchant/appcheck/apps' -ForegroundColor DarkGray
Write-Host ''
