# Restrict Google Maps / Directions keys (van2)

> คู่มือ ops — ลดความเสี่ยง abuse API key ที่ฝังใน client

## Android Maps SDK (AndroidManifest)

- **van2** key ใน `android/app/src/main/AndroidManifest.xml` — รัน: `scripts/add-van2-upload-sha1-maps-key.ps1`
- **van1** key (API key 4, ...GsU) — รัน: `scripts/restrict-van1-maps-android-key.ps1`
- เพิ่ม package + SHA-1 **upload keystore** (ไม่ใช่แค่ debug) ก่อนขึ้น Play Store

## Web Maps JS

- Fallback key: `lib/config/google_maps_web_api_key_fallback_web.dart`
- รัน: `scripts/fix-web-maps-browser-key.ps1` (HTTP referrer van*.web.app + Maps JS API)

## Server Directions (Cloud Functions)

- ใช้ secret `GOOGLE_GEOCODING_API_KEY` — restrict ด้วย IP ของ Cloud Functions หรือ API-only key
- ใช้โดย: `computeRouteMetrics`, `createTravelOrder` (server-side distance)

## ห้าม

- อย่า commit `key.properties` หรือ keystore
- อย่าใช้ unrestricted key ใน production
