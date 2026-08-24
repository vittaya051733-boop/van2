# Van Ecosystem — Schema Registry (field contracts ที่ข้ามแอป)

> อ่านคู่กับ `VAN_ECOSYSTEM_CROSS_WRITE.md`  
> กฎ default: **Expand (เพิ่ม field) ก่อน → Migrate consumer → Contract (ลบทีหลัง)**  
> ห้าม rename/ลบ field จนแอปที่อ่าน deploy ครบ

Project: **van-merchant** · DB: `(default)`

---

## กลุ่ม A — โปร / ราคา / หน้าแรก

| Collection | Field สำคัญ | Writer | Reader | Default ถ้าไม่มี |
|------------|-------------|--------|--------|------------------|
| `coupons/{id}` | `presentation`, `display.transparentImage`, `conditions.productIds`, `conditions.shopIds`, `maxClaims`, `expiresAt` | van4 | van2 | presentation=`inline` หรือข้าม popup |
| `promotions/{id}` | ตาม schema โปร | van4 | van2 | ข้ามรายการ |
| `promotion_display_config/global` | config แสดงผล | van4 | van2 | ใช้ค่าในโค้ด van2 |
| `pricing_config/global` | อัตรา/ค่าส่ง | van4 | van2 | ค่า fallback ใน `pricing_config_service` |
| `platform_catalog/home_shelves` | `featuredProductIds`, `quickActions`, `homeLock` | van4 | van2 | ไม่มี `quickActions` = เปิดทุกปุ่ม; ไม่มี `homeLock` = หน้าโฮมใช้งานได้ |

## กลุ่ม B — แจ้งเตือน

| Collection | Field สำคัญ | Writer | Reader | Default |
|------------|-------------|--------|--------|---------|
| `app_notifications/{id}` | `action`, `title`, `body`, `userId` | van4/CF | van1,2,3 | แสดง generic ถ้า action ไม่รู้จัก |
| `platform_announcements` | metadata | van4 | van2 (บางหน้า) | ข้าม |

## กลุ่ม C — Catalog

| Collection | Field สำคัญ | Writer | Reader | Default |
|------------|-------------|--------|--------|---------|
| `products/{id}` | `isActive`, `catalogReviewStatus`, stock, variants | van1/van4 | van2, van1 | ซ่อนถ้าไม่ active |
| `public_shops/{id}` | mirror ร้าน | van4/CF | van2, van1, van3 | ข้ามร้าน |

## กลุ่ม D — Orders / wallet

| Path | Field สำคัญ | Writer | Reader | Default |
|------|-------------|--------|--------|---------|
| `orders/{id}` | `status`, `settlement`, `shopPayout`, `riderPayout`, `driverId`, `shopOwnerId`, `customerId` | van2 CF / van4 | van1,2,3 | UI แสดง "—" ถ้าไม่มี payout |
| `credits/{uid}` | `balance` | CF | van1, van3 | 0 |
| `withdraw_requests` | status | CF | van1, van3, van4 | ข้ารายการ |

## กลุ่ม E — Admin

| Collection | หมายเหตุ |
|------------|----------|
| `admins`, `admin_presence`, `admin_internal_threads` | van4 เป็นหลัก |
| `admin_support_tickets` | user ทุก van สร้างได้; van4 ตอบ |

## กลุ่ม E2 — Ecosystem heartbeats

| Path | Field สำคัญ | Writer | Reader | Default |
|------|-------------|--------|--------|---------|
| `ecosystem_heartbeats/{appId}/sessions/{uid}` | `appId`, `uid`, `firestoreOk`, `updatedAt`, `platform`, `points`, `lastError`, `errorCode` | van1/2/3/4 (own session) | van4 admin | ถ้าไม่มี session สด → จุด van1/2/3 = unknown/แดง (ไม่มี heartbeat) |

---

## Checklist ก่อนเพิ่ม field

1. ระบุ collection + field ใหม่ใน PR นี้
2. Consumer มี default / optional parse
3. อย่าลบ field เก่าใน PR เดียวกับที่เพิ่ม (แยก Contract ทีหลัง)
4. ถ้า CROSS-WRITE → ระบุ Bundle ที่เกี่ยว (A01/A02/B01/C01/D01)
5. บันทึกใน commit: `schema: coupons.presentation → van2 claimable`

## อัปเดต

สร้าง 2026-08-13 · แก้ field ข้ามแอป → อัปเดตไฟล์นี้ใน PR เดียวกัน
