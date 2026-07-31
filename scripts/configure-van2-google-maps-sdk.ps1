# เปิด Google Cloud Console เพื่อเพิ่ม Van2.com ให้ Maps SDK key
# รันแล้วทำตามขั้นตอนใน Console (ครั้งเดียว)

$ErrorActionPreference = 'Stop'

$keyId = 'AIzaSyABo43mqmfEuAQJ4CKnzl6dePIIoGyyGsU'
$package = 'Van2.com'
$sha1 = '17:D5:1E:94:74:3C:DD:99:58:BB:43:89:87:6F:EB:67:D6:8E:60:61'
$project = 'van-merchant'

Write-Host ''
Write-Host '=== van2 Google Maps SDK setup ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Maps SDK key (shared with van1 van.merchant):' $keyId
Write-Host 'Android package (van2):' $package
Write-Host 'Debug SHA-1:' $sha1
Write-Host ''
Write-Host 'Use the SAME key as van.merchant — just ADD Van2.com (do not remove van.merchant).' -ForegroundColor Green
Write-Host ''
Write-Host 'Steps in Google Cloud Console:' -ForegroundColor Yellow
Write-Host '1. Open Maps SDK for Android API'
Write-Host '   https://console.cloud.google.com/apis/library/maps-android-backend.googleapis.com?project=' $project
Write-Host '2. Open Credentials and edit key ending in ...GsU (same as van1)'
Write-Host '   https://console.cloud.google.com/apis/credentials?project=' $project
Write-Host '3. Application restrictions -> Android apps -> Add (keep van.merchant):'
Write-Host "     Package: $package"
Write-Host "     SHA-1:   $sha1"
Write-Host '4. API restrictions -> include Maps SDK for Android'
Write-Host '5. Save, wait 1-2 minutes, rebuild van2 APK'
Write-Host ''
Write-Host 'Rebuild after GCP change:' -ForegroundColor Green
Write-Host '  powershell -File scripts\run-van2-by-avd.ps1'
Write-Host ''

Start-Process 'https://console.cloud.google.com/apis/credentials?project=van-merchant'
