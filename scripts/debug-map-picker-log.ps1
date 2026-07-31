param(
    [string]$Serial = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$localPropsPath = Join-Path $appRoot 'android\local.properties'

function Set-LocalProperty {
    param([string]$FilePath, [string]$Key, [string]$Value)
    $lines = @()
    if (Test-Path $FilePath) { $lines = Get-Content $FilePath }
    $filtered = @($lines | Where-Object { $_ -notmatch "^$([regex]::Escape($Key))=" })
    $filtered += "$Key=$Value"
    Set-Content -Path $FilePath -Value $filtered -Encoding utf8
}

Set-LocalProperty -FilePath $localPropsPath -Key 'useVan1MapsIdentity' -Value 'true'

Write-Host 'Building debug APK with DEBUG_MAP_PICKER...' -ForegroundColor Cyan
flutter build apk --debug `
    --dart-define=APP_CHECK_DEBUG=true `
    --dart-define=DEBUG_MAP_PICKER=true `
    --dart-define=FIREBASE_ANDROID_APP_ID=1:802503541368:android:c8333c4310663e19f6a38d `
    --dart-define=FIREBASE_ANDROID_STORAGE_BUCKET=van-merchant-van1-storage-802503541368

$apk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
& $adb -s $Serial logcat -c | Out-Null
& $adb -s $Serial install -r -d $apk | Out-Null
& $adb -s $Serial shell am force-stop van.merchant | Out-Null
Start-Sleep -Seconds 1
& $adb -s $Serial shell am start -n van.merchant/van.merchant.MainActivity | Out-Null

Write-Host 'Waiting 20s for Google Maps to initialize...' -ForegroundColor Cyan
Start-Sleep -Seconds 20

Write-Host ''
Write-Host '=== MAPS LOG (filtered) ===' -ForegroundColor Yellow
& $adb -s $Serial logcat -d | Select-String -Pattern `
    'Authorization|API_KEY|INVALID_ARGUMENT|Maps SDK|Google Maps|GoogleMap|geo\.API|MapView|m140\.|ApiException|DEVELOPER_ERROR|ApiKey|token' `
    -CaseSensitive:$false

Write-Host ''
Write-Host '=== PACKAGE / KEY INFO ===' -ForegroundColor Yellow
& $adb -s $Serial shell dumpsys package van.merchant | Select-String 'versionCode|versionName' | Select-Object -First 2

$keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
$debugKeystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if ((Test-Path $keytool) -and (Test-Path $debugKeystore)) {
    Write-Host ''
    Write-Host 'Debug SHA-1:' -ForegroundColor Yellow
    & $keytool -list -v -keystore $debugKeystore -alias androiddebugkey -storepass android -keypass android 2>$null |
        Select-String 'SHA1:'
}
