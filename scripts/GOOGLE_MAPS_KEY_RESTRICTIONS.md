# Restrict Google Maps / Directions keys (van2)

> คู่มือ ops — ลดความเสี่ยง abuse API key ที่ฝังใน client

## Android Maps SDK (AndroidManifest)

- Key ใน `android/app/src/main/AndroidManifest.xml` ต้อง restrict ใน GCP
- รัน: `scripts/configure-van2-google-maps-sdk.ps1`
- เพิ่ม package `Van2.com` + SHA-1 **upload keystore** (ไม่ใช่แค่ debug) ก่อนขึ้น Play Store

## Web Maps JS

- Fallback key: `lib/config/google_maps_web_api_key_fallback_web.dart`
- Restrict ด้วย HTTP referrer (domain van2 hosting เท่านั้น)

## Server Directions (Cloud Functions)

- ใช้ secret `GOOGLE_GEOCODING_API_KEY` — restrict ด้วย IP ของ Cloud Functions หรือ API-only key
- ใช้โดย: `computeRouteMetrics`, `createTravelOrder` (server-side distance)

## ห้าม

- อย่า commit `key.properties` หรือ keystore
- อย่าใช้ unrestricted key ใน production
