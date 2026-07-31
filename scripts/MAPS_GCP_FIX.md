# Fix van2 Google Maps (from logcat diagnosis)

## Root cause (`scripts/debug-map-picker-log.ps1`)

```
Google Android Maps SDK: Authorization failure.
API Key: AIzaSyCuGZF0-EUBTuARrToDWQM5pNBMNDg2yYU
Android Application: 17:D5:1E:94:74:3C:DD:99:58:BB:43:89:87:6F:EB:67:D6:8E:60:61;van.merchant
```

Firebase Android key ไม่ได้ลงทะเบียน **Maps SDK for Android** + SHA-1 debug + package

## Fix applied (GCP project `van-merchant`)

1. Enabled `maps-android-backend.googleapis.com`
2. Updated Firebase Android key resource `3b9e3186-50da-45c8-9d79-22fe437b6672`:
   - `van.merchant` + debug SHA-1
   - `Van2.com` + debug SHA-1
   - API target: Maps SDK for Android (+ Firebase APIs เดิม)
3. `AndroidManifest.xml` ใช้ Firebase Android key (`AIzaSyCuGZF0-...`)

## Verify

```powershell
powershell -File scripts\debug-map-picker-log.ps1
```

Log ต้อง **ไม่มี** `Authorization failure` และมี `Network fetching: true`

## Production release SHA-1

เมื่อ sign release ให้เพิ่ม release SHA-1 ใน key เดียวกัน (package `Van2.com`)
