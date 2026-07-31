# van2 Pre-Store Risk Register

> อัปเดต: 2026-07-31  
> บันทึกหลัง deploy security fixes + re-audit  
> อ่านคู่กับ `DEPLOY_GOVERNANCE.md`, `DEPLOY_RISK_MATRIX.md`

## สรุปสถานะ

| หมวด | สถานะ |
|------|--------|
| 8 security fixes หลัก | deploy แล้ว (CF + Firestore rules) |
| รอบที่ 2 (discount/travel/OTP/rules) | deploy แล้ว (2026-07-31) |
| Client APK 1.0.2+5 | build แล้ว — **debug signing** (ยังไม่พร้อม Play Store) |
| รายการด้านล่าง § C | **ยังไม่แก้** — แนะนำก่อน/หลังขึ้น Store |

### โค้ดที่ deploy แล้ว (รอบ 2)

- `AppCheckGuard` retry token + web reCAPTCHA check
- `cart_screen` / `nationwide_cart_screen` เรียก guard ก่อน CF
- `recordCheckoutDiscounts` verify quote + orders + enforceAppCheck
- `createTravelOrder` server Google Directions distance
- `sendEmailOtp` / `verifyEmailOtp` enforceAppCheck
- Firestore `products` create/update/delete block anonymous
- `scripts/GOOGLE_MAPS_KEY_RESTRICTIONS.md`

---

## A. จุดเสี่ยงล้ม (Outage)

### A1 — Release APK debug-signed + Play Integrity (CRITICAL)

**อาการ:** ตะกร้าไม่คำนวณราคา, checkout/Omise/travel ล้ม `app-check`  
**สาเหตุ:** release build ใช้ `AndroidPlayIntegrityProvider` แต่ APK sign ด้วย debug keystore / ยังไม่ register SHA ใน Firebase App Check  
**แก้:**

1. สร้าง upload keystore → `android/key.properties` (ดู `key.properties.example`)
2. Firebase Console → App Check → Android `Van2.com` → Play Integrity + SHA-256 upload cert
3. `scripts/build-android-release.ps1` (ห้าม `-AllowDebugSigning` สำหรับ store)

### A2 — App Check fail → cart/checkout (HIGH)

**อาการ:** เปิดแอปได้ แต่ราคาไม่ขึ้น / กดชำระไม่ได้  
**สาเหตุ:** `calculateCartTotals` มี `enforceAppCheck` แต่ token ไม่พร้อมตอน startup  
**แก้ (โค้ด):** `AppCheckGuard` + retry token ใน cart/nationwide/checkout flows

### A3 — Web ไม่มี reCAPTCHA App Check key (HIGH — web only)

**อาการ:** van2 web checkout/login CF ล้มทั้งหมด  
**แก้:** build web ด้วย `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=...` + register ใน Firebase App Check

---

## B. ช่องโหว่ (ไม่ crash แต่เสียหายได้)

### B1 — recordCheckoutDiscounts abuse (HIGH)

**อาการ:** user ปลอม redemption coupon/promo  
**แก้ (โค้ด):** verify `checkoutQuoteId`, order ownership, discountTotal จาก quote + `enforceAppCheck`

### B2 — Travel fare under-report (HIGH)

**อาการ:** client ส่ง distance ต่ำ → ค่าโดยสารถูกกว่าจริง  
**แก้ (โค้ด):** server คำนวณ route ผ่าน Google Directions, คิด fare จาก server distance

### B3 — Maps API key / OTP spam (MEDIUM)

**Maps:** restrict key ใน GCP (Android package + SHA) — `scripts/configure-van2-google-maps-sdk.ps1`  
**OTP:** `enforceAppCheck` บน `sendEmailOtp` / `verifyEmailOtp` + rate limit เดิม

---

## C. รายการที่ยังเหลือ (Re-audit หลัง deploy)

### C1 — Travel Omise จ่ายก่อน สร้างออเดอร์ทีหลัง — **แก้แล้ว (2026-07-31)**

- CF `quoteTravelFare` + client `TravelFareQuoteService` ก่อน Omise charge
- Deploy: `quoteTravelFare` (CF ใหม่)

### C2 — Login OTP + App Check guard — **แก้แล้ว (2026-07-31)**

- `AppCheckGuard.ensureAuthReady()` ใน login + auth_verification

### C3 — CF App Check — **แก้แล้ว (2026-07-31)**

- `enforceAppCheck` บน lookupLogin, maps CFs, syncVan2CartStockHold
- Client guard ก่อนเรียก CF ที่เกี่ยวข้อง
- Deploy: `quoteTravelFare`, `lookupLoginIdentifier`, `computeRouteMetrics`, `placesAutocomplete`, `placesResolvePlace`, `reverseGeocodeDeliveryLocation`, `syncVan2CartStockHold`

### C4 — recordCheckoutDiscounts ล้มเงียบ — **แก้แล้ว (2026-07-31)**

- retry 1 ครั้ง + SnackBar แจ้ง user

### C5 — Maps API keys ใน client (MEDIUM — ค่าใช้จ่าย)

- Web fallback key ใน `google_maps_web_api_key_fallback_web.dart`
- AndroidManifest Maps SDK key  
→ restrict ตาม `GOOGLE_MAPS_KEY_RESTRICTIONS.md`

### C6 — Manual ops ก่อน Store

- [x] `android/key.properties` + upload keystore
- [ ] Firebase App Check: Play Integrity + SHA-256 upload cert (ยืนยันใน Console)
- [ ] Web: `--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=...`

---

## Checklist ก่อนขึ้น Store

- [x] Upload keystore + `key.properties`
- [ ] Firebase App Check: Play Integrity + SHA-256
- [ ] Release APK smoke: login OTP → cart → COD → Omise → travel Omise
- [ ] GCP: restrict Maps keys (upload SHA-1)
- [ ] (Web) reCAPTCHA site key ใน build
- [x] Deploy CF รอบ 2
- [x] Deploy CF รอบ 3: `quoteTravelFare`, lookup/maps/sync CFs (2026-07-31)
- [x] แก้ C1 travel Omise quote ก่อน pay
- [x] แก้ C2 App Check guard ที่ login OTP
- [x] แก้ C3/C4 client + server

---

## Deploy คำสั่ง (หลังแก้โค้ด)

```powershell
cd van2\scripts
.\deploy-self.ps1 -App van2 -Target functions -FunctionName recordCheckoutDiscounts -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
.\deploy-self.ps1 -App van2 -Target functions -FunctionName createTravelOrder -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
.\deploy-self.ps1 -App van2 -Target functions -FunctionName sendEmailOtp -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
.\deploy-self.ps1 -App van2 -Target functions -FunctionName verifyEmailOtp -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```

Firestore (ถ้าแก้ rules anonymous products update):

```powershell
.\deploy-self.ps1 -App van2 -Target firestore -ConfirmDeploy "APPROVE:van2:van-merchant" -ConfirmImpact "SHARED:van1,van2,van3,van4" -FinalAcknowledge "YES I UNDERSTAND"
```
