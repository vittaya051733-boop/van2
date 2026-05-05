param(
    [string]$Serial,
    [string]$AvdName = 'van2'
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

$apk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
$packageName = 'van.merchant'
$activityName = 'van.merchant.MainActivity'

Write-Host "Building van2 debug APK for $target" -ForegroundColor Cyan
$buildArgs = @(
    'build',
    'apk',
    '--debug',
    '--dart-define=APP_CHECK_DEBUG=true'
)

if ($env:GOOGLE_MAPS_WEB_API_KEY) {
    $buildArgs += "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$($env:GOOGLE_MAPS_WEB_API_KEY)"
} else {
    Write-Warning 'GOOGLE_MAPS_WEB_API_KEY is not set. Google Places/Geocoding search may not work.'
}

flutter @buildArgs

if (-not (Test-Path $apk)) {
    Write-Error "APK not found at path: $apk"
    exit 1
}

Write-Host "Installing APK via adb --no-streaming on $target" -ForegroundColor Cyan
& $adb -s $target install --no-streaming -r $apk

Write-Host "Launching $packageName on $target" -ForegroundColor Cyan
& $adb -s $target shell am force-stop $packageName | Out-Null
& $adb -s $target shell am start -n "$packageName/$activityName"

Write-Host "Attaching Flutter debugger to $target" -ForegroundColor Cyan
$attachArgs = @(
    'attach',
    '-d',
    $target
)

flutter @attachArgs
