# Van Ecosystem — ตาราง CROSS-WRITE (van4/admin → แอปอื่นอ่าน)

> อ่านคู่กับ `DEPLOY_RISK_MATRIX.md` และ `DEPLOY_GOVERNANCE.md`  
> **van4 เขียน → van1/van2/van3 อ่าน** = ต้องแก้ consumer + backward compatible ก่อน deploy

Project: **`van-merchant`** — Firestore DB `(default)` แชร์ van1, van2, van3, van4 (admin)

---

## สัญลักษณ์

| สัญลักษณ์ | ความหมาย |
|-----------|----------|
| **W** | van4 admin เขียนตรง (client หรือ CF ที่ van4 เรียก) |
| **R** | แอปอื่นอ่าน/listen |
| **CF** | เขียนผ่าน Cloud Functions เท่านั้น (van4 UI เรียก callable) |
| **—** | ไม่เกี่ยว |

---

## กลุ่ม A — Platform config (van4 → van2 เป็นหลัก)

| Collection / doc | van4 เขียน | van2 อ่าน | van1 | van3 | ไฟล์ van4 (write) | ไฟล์ consumer หลัก |
|------------------|------------|-----------|------|------|-------------------|---------------------|
| `pricing_config/global` | **W** | **R** listen | — | — | `admin_pricing_config_screen.dart` | `van2/pricing_config_service.dart` |
| `promotion_display_config/global` | **W** | **R** listen | — | — | `admin_promotions_screen.dart` | `van2/services/promotion_display_config_service.dart` |
| `coupons/{id}` | **W** | **R** listen | — | — | `admin_promotions_screen.dart` | `van2/services/claimable_coupon_service.dart`, `main.dart` |
| `promotions/{id}` | **W** | **R** listen | — | — | `admin_promotions_screen.dart` | `van2/services/promotion_catalog_service.dart` |
| `platform_catalog/home_shelves` | **W** | **R** listen | — | — | `admin_repository.dart`, `admin_home_shelves_screen.dart` | `van2/public_catalog_service.dart`, `home_product_discovery_service.dart`, `home_quick_action_config_service.dart`, `main.dart` |
| `platform_config/settlement` | **W** | — | — | — | `admin_settlement_support.dart` | *(van2/van1/van3 อ่านผ่าน field `orders.settlement` + CF checkout)* |
| `platform_config/leader` | **W** | — | — | — | `admin_settlement_support.dart` | *(payout backend)* |

**กฎ:** เปลี่ยน field ในกลุ่ม A → ต้องเช็ค **van2** ทุกครั้ง (cart, หน้าแรก, โปร/คูปอง). Field ใหม่ต้องมี **default** ใน consumer.

---

## กลุ่ม B — แจ้งเตือน / ประกาศ (van4 → ทุกแอป)

| Collection | van4 เขียน | van1 | van2 | van3 | หมายเหตุ |
|------------|------------|------|------|------|----------|
| `platform_announcements` | **W** | — | R (admin tab) | — | metadata ประกาศ |
| `app_notifications` | **W** batch | **R** | **R** | **R** | fan-out ต่อ user; `action: admin_announcement` |

**ไฟล์ van4:** `admin_announcement_support.dart`, `admin_repository.dart`, `admin_settlement_support.dart`  
**Consumer:** `notification_service.dart` / `notifications_screen.dart` ในแต่ละ van

**กฎ:** เปลี่ยน `action` string หรือ payload shape → ต้องเทส FCM + inbox **van1, van2, van3**

---

## กลุ่ม C — สินค้า / ร้าน / คataloก (van4 → van2 + van1)

| Collection | van4 เขียน | van2 | van1 | van3 | หมายเหตุ |
|------------|------------|------|------|------|----------|
| `products/{id}` | **W** | **R** listen | **R** own | — | approve catalog, admin create |
| `product_admin_reviews/{id}` | **W** | — | **R** | — | คิว AI รอตรวจ |
| `public_shops/{id}` | **W** | **R** | **R** | **R** | mirror หลังอนุมัติร้าน |
| `*_registrations` | **W** | — | **R** | — | อนุมัติร้าน |

**กฎ:** เปลี่ยน visibility (`isActive`, `catalogReviewStatus`, stock) → กระทบ **van2 catalog** ทันที (real-time listener)

---

## กลุ่ม D — ออเดอร์ / settlement (van4 → van1 + van3)

| Path | van4 เขียน | van1 | van2 | van3 | หมายเหตุ |
|------|------------|------|------|------|----------|
| `orders/{id}` | **W** / **CF** | **R** | **R** | **R** | cancel, payout status, credit release |
| `orders/{id}/timeline` | **W** | **R** | **R** | **R** | admin cancel event |
| `withdraw_requests` | **CF** | **R** | — | **R** | van4 UI เรียก CF ไม่เขียนตรง |

**กฎ:** เปลี่ยน `settlement`, `shopPayout`, `riderPayout` → เทส **wallet van1 + van3**

---

## กลุ่ม E — Admin-only (ไม่มี consumer ใน van1/2/3)

| Collection | van4 | van1/2/3 |
|------------|------|----------|
| `admins/{email}` | **W** | — |
| `admin_presence/{uid}` | **W** | — |
| `admin_internal_threads` | **W** | — |
| `admin_support_tickets` | **W** | **R** (inbox ฝั่ง user ทุก van) |
| `admin_support_knowledge` | **W** | — |
| `project_finance` | **W** | — |
| `contracts` | **W** | — |
| `riders`, `rider_registrations` | **W** | **R** van3 |

---

## กลุ่ม E2 — Ecosystem health heartbeats (van1/2/3/4 เขียน → van4 อ่าน)

| Path | Writer | Reader | หมายเหตุ |
|------|--------|--------|----------|
| `ecosystem_heartbeats/{appId}/sessions/{uid}` | van1, van2, van3, van4 (client, own uid) | **van4 admin** (`isPrivilegedAdmin`) | แดง/เขียวจุดเชื่อมจากแอปจริง — ไม่ใช่แค่ probe จาก van4 |

**Field (expand-only):** `appId`, `uid`, `firestoreOk`, `updatedAt`, `platform`, `points` (map pointId→bool), `lastError`, `errorCode`

**กฎ:** แก้ schema → อัปเดต consumer ใน `van4/lib/services/ecosystem_health_service.dart` + writers ใน van1/2/3  
**Deploy rules:** SHARED จาก van2 (`BUNDLE-S01`) + smoke van3

---

## กลุ่ม F — Cloud Functions (van2 canonical, ทุกแอปเรียก)

| Callable / trigger | deploy จาก | เรียกจาก |
|--------------------|------------|----------|
| `claimCoupon` | van2 | van2 |
| checkout / order lifecycle | van2 | van2 |
| `pushAppNotification` | van2 | backend |
| withdraw approve/reject | van2 | van4 |
| `adminUpdateOrderCreditRelease` | van2 | van4 |

**กฎ:** แก้ function ใน van2 → ระบุว่า van ไหนเรียก; deploy **ทีละชื่อ** + smoke

---

## Checklist ก่อน merge/deploy (CROSS-WRITE)

เมื่อแก้ van4 ที่เขียน collection ในกลุ่ม A–D:

- [ ] ระบุ collection + field ที่เปลี่ยน
- [ ] เปิด consumer ใน van2/van1/van3 (ตารางด้านบน)
- [ ] Field ใหม่: consumer ใช้ default ถ้าไม่มี (backward compatible)
- [ ] ลบ/rename field: **ห้าม** จนกว่า consumer ทุกตัว deploy แล้ว
- [ ] ถ้าแตะ rules → deploy จาก **van2** + smoke **van3 ไรเดอร์** ทันที
- [ ] บันทึกใน commit message: `cross-write: coupons → van2 claimable_coupon_service`

---

## ไม่ใช่ Firestore (แต่แชร์ project)

| ทรัพยากร | กระทบ |
|----------|-------|
| Firebase Auth | ทุก van |
| App Check (debug token / Play Integrity) | ทุก van — แยกต่อแอปใน Console |
| FCM | ทุก van |
| Storage bucket | แยก per van (deploy SELF) |

---

## อัปเดตล่าสุด

สร้างจาก codebase audit — 2026-08-11. ถ้าเพิ่ม collection ใหม่ใน van4 ให้อัปเดตไฟล์นี้ใน PR เดียวกัน.
