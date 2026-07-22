# Google Maps Search Setup

ไฟล์นี้ใช้สำหรับแยก `Google Maps SDK key` ออกจาก `Google Maps Web Service key` ที่หน้าเลือกจุดรับ-ส่งใช้ค้นหาสถานที่

## สถานะปัจจุบัน

- `Android/iOS SDK key` ใช้ **key เดียวกับ van1 (van.merchant)**: `AIzaSyABo43mqmfEuAQJ4CKnzl6dePIIoGyyGsU` ใน `AndroidManifest.xml` และ `AppDelegate.swift`
- `Web JS key` ใช้ Firebase Web key (`AIzaSyB6Q5DE_...`) ใน `web/index.html`
- ใน GCP ให้ **เพิ่ม** `Van2.com` + SHA-1 debug คู่กับ `van.merchant` บน key เดียวกัน (ไม่ต้องสร้าง key ใหม่)
- **ทางลัดสำหรับ emulator:** `scripts/run-van2-by-avd.ps1` จะ build ด้วย package `van.merchant` (key เดียวกับ van1) โดยอัตโนมัติ — ไม่ต้องแก้ GCP
- Production release ยังใช้ `Van2.com` ได้ด้วย `-UseVan2Package` (ต้องเพิ่ม Van2.com ใน GCP ก่อนแผนที่จะขึ้น)
- `Places Autocomplete`, `Place Details`, และ `Geocoding API` จะอ่านจาก `GOOGLE_MAPS_WEB_API_KEY`
- ถ้ายังไม่ส่ง `GOOGLE_MAPS_WEB_API_KEY` เข้าแอพ การค้นหาสถานที่จะไม่ทำงาน แต่ยังปักหมุดบนแผนที่ได้

## Google Cloud Console

เปิดหน้าเหล่านี้หลังจาก sign in:

- https://console.cloud.google.com/apis/library/places-backend.googleapis.com
- https://console.cloud.google.com/apis/library/geocoding-backend.googleapis.com
- https://console.cloud.google.com/apis/credentials

## ถ้าแผนที่ยังว่างบน Android

1. เปิด https://console.cloud.google.com/apis/library/maps-android-backend.googleapis.com
2. เปิด **Maps SDK for Android** ใน project `van-merchant`
3. ไปที่ Credentials แล้วตรวจ key `AIzaSyABo43mqmfEuAQJ4CKnzl6dePIIoGyyGsU` (key เดียวกับ van1)
4. ตั้ง Application restrictions = Android apps แล้ว **เพิ่ม** (อย่าลบ van.merchant):
   - Package: `Van2.com`
   - SHA-1: `17:D5:1E:94:74:3C:DD:99:58:BB:43:89:87:6F:EB:67:D6:8E:60:61`
5. ตั้ง API restrictions ให้รวม **Maps SDK for Android**
6. Build ใหม่ด้วย `scripts/run-van2-by-avd.ps1` (hot reload ไม่พอ ต้อง reinstall APK)

## ขั้นตอนที่ต้องทำ

1. เลือก Google Cloud project ที่ key ปัจจุบันใช้อยู่
2. เปิด `Places API`
3. เปิด `Geocoding API`
4. ไปที่ `APIs & Services > Credentials`
5. สร้าง API key ใหม่ เช่น `van2-places-web-service`
6. ตั้ง `API restrictions` ให้ key ใหม่นี้ใช้ได้เฉพาะ:
   - `Places API`
   - `Geocoding API`
7. ถ้าจะเรียกจาก Flutter app ตรง ๆ แบบตอนนี้ อย่าตั้ง `Application restrictions` เป็น Android/iOS app restriction เพราะ Google จะปฏิเสธ web service call
8. ถ้าต้องการความปลอดภัยจริง ควรย้าย Places/Geocoding ไปเรียกผ่าน backend/proxy แล้วค่อยตั้ง restriction ฝั่ง server

## PowerShell

ตั้ง environment variable ชั่วคราวใน terminal ปัจจุบัน:

```powershell
$env:GOOGLE_MAPS_WEB_API_KEY = 'PUT_YOUR_NEW_WEB_SERVICE_KEY_HERE'
```

รันแอพผ่านสคริปต์เดิม:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-van2-by-avd.ps1
```

หรือรันตรง:

```powershell
flutter run -d emulator-5554 --dart-define=APP_CHECK_DEBUG=true --dart-define=GOOGLE_MAPS_WEB_API_KEY=$env:GOOGLE_MAPS_WEB_API_KEY
```

## จุดที่อ้างอิงในโค้ด

- `lib/map_picker_screen.dart` ใช้ `GOOGLE_MAPS_WEB_API_KEY` สำหรับค้นหา
- `android/app/src/main/AndroidManifest.xml` ยังเก็บ SDK key สำหรับ Google Maps Android SDK
- `ios/Runner/AppDelegate.swift` ยังเก็บ SDK key สำหรับ Google Maps iOS SDK

## หมายเหตุ

- ถ้า Google Cloud Console ยังพาไปหน้า sign in บนเครื่องนี้ ต้อง sign in ให้เสร็จก่อนจึงจะกดเปิด API หรือสร้าง key ได้
- ถ้าเปิด API แล้วแต่ยังขึ้น `REQUEST_DENIED` ให้กลับไปตรวจ `API restrictions` ของ key ใหม่อีกครั้ง
