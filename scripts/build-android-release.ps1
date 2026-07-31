# Build van2 Android release (AAB + optional APK).
# Requires android/key.properties — see android/key.properties.example
param(
    [switch]$Apk,
    [switch]$SkipClean,
    [switch]$AllowDebugSigning
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$keyProps = Join-Path $root "android\key.properties"
$usingDebugSigning = -not (Test-Path $keyProps)
if ($usingDebugSigning -and -not $AllowDebugSigning) {
    Write-Error @"
Missing android/key.properties — copy android/key.properties.example and configure your upload keystore before store release.
For internal QA only, rerun with -AllowDebugSigning (uses debug keystore; not for Play Store).
"@
}
if ($usingDebugSigning) {
    Write-Warning "Building with debug signing — OK for QA sideload, NOT for Play Store upload."
}

if (-not $SkipClean) {
    flutter clean
    flutter pub get
}

$version = (Select-String -Path (Join-Path $root "pubspec.yaml") -Pattern "^version:\s*(.+)$").Matches.Groups[1].Value.Trim()
$releasesDir = Join-Path $root "releases"
if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Path $releasesDir | Out-Null
}

$crashlyticsFlag = "-PfirebaseCrashlyticsMappingFileUploadEnabled=false"

if ($Apk) {
    flutter build apk --release --no-pub $crashlyticsFlag
    $apkSrc = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
    $apkDst = Join-Path $releasesDir "van2-$version-release.apk"
    Copy-Item $apkSrc $apkDst -Force
    Write-Host "APK: $apkDst"
} else {
    flutter build appbundle --release --no-pub $crashlyticsFlag
    $aabSrc = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
    $aabDst = Join-Path $releasesDir "van2-$version-release.aab"
    Copy-Item $aabSrc $aabDst -Force
    Write-Host "AAB: $aabDst"
}
