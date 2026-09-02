# Van Ecosystem — Schema Registry (field contracts ที่ข้ามแอป)

> อ่านคู่กับ `VAN_ECOSYSTEM_CROSS_WRITE.md`  
> กฎ default: **Expand (เพิ่ม field) ก่อน → Migrate consumer → Contract (ลบทีหลัง)**  
> ห้าม rename/ลบ field จนแอปที่อ่าน deploy ครบ

Project: **van-merchant** · DB: `(default)`

---

## กลุ่ม A — โปร / ราคา / หน้าแรก

| Collection | Field สำคัญ | Writer | Reader | Default ถ้าไม่มี |
|------------|-------------|--------|--------|------------------|
| `coupons/{id}` | `presentation`, `display.transparentImage`, `conditions.productIds`, `conditions.shopIds`, `maxClaims`, `expiresAt`, `distribution` (`self_claim` / `admin_grant`), `assigneeUid`, `originOrderId` | van4 / CF | van2 | presentation=`inline` หรือข้าม popup; `admin_grant` ไม่โชว์ป๊อปอัพ self-claim |
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
| `products/{id}` | `isActive`, `catalogReviewStatus`, stock, variants, **`nameEn`**, **`descriptionEn`**, **`translationSource`**, **`translatedAt`** (van2 CF แปล cache) | van1/van4 write หลัก; van2 CF เขียน EN | van2, van1 | ซ่อนถ้าไม่ active; ไม่มี `nameEn` → แสดง `name` (TH) |
| `public_shops/{id}` | mirror ร้าน | van4/CF | van2, van1, van3 | ข้ามร้าน |

## กลุ่ม D — Orders / wallet

| Path | Field สำคัญ | Writer | Reader | Default |
|------|-------------|--------|--------|---------|
| `orders/{id}` | `status`, `settlement`, `shopPayout`, `riderPayout`, `driverId`, `shopOwnerId`, `customerId`, **`branchId`**, **`branchName`**, `marketId` (legacy alias), `orderType`, `originOrderId`, `claimId`, `claimStatus`, `replacementOrderId`, `claimCreditCouponId` | van2 CF / van4 | van1,2,3, van4 branch filter | ไม่มี `branchId` → van4 resolve จาก shop; rules branch admin ใช้ `branchId` |
| `coupons/{id}` | … + optional **`branchId`** | van4 | van2 | null/ไม่มี = global (super admin only write) |
| `promotions/{id}` | … + optional **`branchId`** | van4 | van2 | null/ไม่มี = global |
| `order_claims/{id}` | `originalOrderId`, `customerId`, `kind` (`replacement`\|`credit`), `reason`, `adminUid`, `replacementOrderId` / `couponId`, `status` | van2 CF | van4 (R) | ไม่มีเอกสาร = ยังไม่เคลม |
| `credits/{creditId}` | `uid`, `amount`, `type` (`top_up`, `order_cod_*`, `withdraw_*`, `admin_adjustment`, …), `reason`, `note`, `adminUid`, `actorType`, `orderId`, `timestamp` | CF / van4 admin CF | van1, van3, van4 | sum(`amount`) where `uid` = balance |
| `credit_admin_actions/{id}` | mirror ของ admin adjust: `creditId`, `uid`, `amount`, `beforeBalance`, `afterBalance`, `reason`, `adminUid`, `actorType`, `createdAt` | van2 CF | van4 | ไม่มี = ไม่มีประวัติปรับมือ |
| `merchant_wallets/{uid}` | `totalCredit`, `withdrawableCredit`, `lockedCredit`, `omise*` | CF sync | van1, van4 | 0 |
| `withdraw_requests` | `amount`, `withdrawFeeBaht`, `netPayout`, `status`, … | CF | van1, van3, van4 | ข้ารายการ |

## กลุ่ม E — Admin

| Collection | Field สำคัญ | Writer | Reader | Default |
|------------|-------------|--------|--------|---------|
| `admins/{email}` | `active`, `authUid`, `displayName`, **`role`** (`super_admin` \| `branch_admin`), **`branchId`**, `branchIds` (optional) | Console / CF `adminProvisionBranchAdmin` | van4 self get | ไม่มี `role` = `super_admin`; branch admin ต้องมี `branchId` |
| `admin_presence`, `admin_internal_threads` | — | van4 | van4 | — |
| `admin_support_tickets` | user ทุก van สร้างได้; van4 ตอบ; `orderId` ออปชัน; `claimRequest` `{ items[], reason, status, claimId? }` เมื่อ `topicKey=product_claim` (expand-only) |

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
