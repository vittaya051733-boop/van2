param(
    [string]$Serial,
    [string]$AvdName = 'van2',
    [switch]$Attach,
    [switch]$UseVan2Package
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$adb = 'C:\Users\TAM\AppData\Local\Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    Write-Error "adb not found at path: $adb"
    exit 1
}

$target = $null
if ($Serial) {
    $target = $Serial.Trim()
}

if (-not $target) {
    $ids = (& $adb devices | Select-String 'emulator-' | ForEach-Object { ($_ -split '\s+')[0] })

    foreach ($id in $ids) {
        $name = (& $adb -s $id emu avd name 2>$null | Select-Object -First 1).Trim()
        if ($name -eq $AvdName) {
            $target = $id
            break
        }
    }
}

if (-not $target) {
    Write-Error "Emulator AVD not found: $AvdName"
    exit 1
}

function Set-LocalProperty {
    param(
        [string]$FilePath,
        [string]$Key,
        [string]$Value
    )

    $lines = @()
    if (Test-Path $FilePath) {
        $lines = Get-Content $FilePath
    }

    $filtered = @($lines | Where-Object { $_ -notmatch "^$([regex]::Escape($Key))=" })
    $filtered += "$Key=$Value"
    Set-Content -Path $FilePath -Value $filtered -Encoding utf8
}

$localPropsPath = Join-Path $appRoot 'android\local.properties'
$useVan1MapsIdentity = -not $UseVan2Package
if ($useVan1MapsIdentity) {
    Set-LocalProperty -FilePath $localPropsPath -Key 'useVan1MapsIdentity' -Value 'true'
    Write-Host 'Using van.merchant package (same Maps SDK key as van1).' -ForegroundColor Green
} else {
    Set-LocalProperty -FilePath $localPropsPath -Key 'useVan1MapsIdentity' -Value 'false'
    Write-Host 'Using Van2.com package (production identity).' -ForegroundColor Yellow
}

$packageName = if ($useVan1MapsIdentity) { 'van.merchant' } else { 'Van2.com' }
$activityName = 'van.merchant.MainActivity'
$apk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'

Write-Host "Building van2 debug APK for $target ($packageName)" -ForegroundColor Cyan
# App Check: default debug token is pinned in lib/main.dart (kVan2AppCheckDebugToken).
# Register it once in Firebase Console -> App Check -> Debug tokens (not every run).
$buildArgs = @(
    'build',
    'apk',
    '--debug',
    '--dart-define=APP_CHECK_DEBUG=true'
)

if ($useVan1MapsIdentity) {
    $buildArgs += @(
        '--dart-define=FIREBASE_ANDROID_APP_ID=1:802503541368:android:c8333c4310663e19f6a38d',
        '--dart-define=FIREBASE_ANDROID_STORAGE_BUCKET=van-merchant-van1-storage-802503541368'
    )
}

if ($env:GOOGLE_MAPS_WEB_API_KEY) {
    Write-Host '[run-van2] GOOGLE_MAPS_WEB_API_KEY from env (optional dev override)' -ForegroundColor Cyan
    $buildArgs += "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$($env:GOOGLE_MAPS_WEB_API_KEY)"
} else {
    Write-Host '[run-van2] Places search uses Cloud Functions on Android (no dart-define needed).' -ForegroundColor DarkGray
}

flutter @buildArgs

if (-not (Test-Path $apk)) {
    Write-Error "APK not found at path: $apk"
    exit 1
}

Write-Host "Installing APK via adb --no-streaming on $target" -ForegroundColor Cyan
if ($useVan1MapsIdentity) {
    & $adb -s $target uninstall Van2.com 2>$null | Out-Null
    Write-Host 'Removed Van2.com to avoid opening the wrong app icon.' -ForegroundColor Yellow
}
& $adb -s $target install --no-streaming -r -d $apk

Write-Host "Launching $packageName on $target" -ForegroundColor Cyan
& $adb -s $target shell am force-stop $packageName | Out-Null
& $adb -s $target shell am start -n "$packageName/$activityName"

if ($Attach) {
    Write-Host "Attaching Flutter debugger to $target" -ForegroundColor Cyan
    $attachArgs = @(
        'attach',
        '-d',
        $target
    )
    flutter @attachArgs
} else {
    Write-Host "App launched. Skipping 'flutter attach' (use -Attach to enable)." -ForegroundColor Green
}
