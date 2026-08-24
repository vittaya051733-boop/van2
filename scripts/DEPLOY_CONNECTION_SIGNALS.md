# สัญญาณการหลุดการเชื่อมต่อ (ข้อ 4)

ใช้หลัง deploy ทุกครั้ง โดยเฉพาะ target **SHARED** (Firestore rules, functions สำคัญ)

## รันครั้งเดียว (แนะนำ)

```powershell
# แผนที่จุดเชื่อมต่อทั้งหมด (ไม่รัน smoke)
van2\scripts\ecosystem-health.ps1 -MatrixOnly

# ตรวจเต็ม: readiness + compile/emulator + checklist มือ
van2\scripts\ecosystem-health.ps1

# โฟกัสแอปเดียว
van2\scripts\ecosystem-health.ps1 -App van3
```

รายการจุดเชื่อม: `ECOSYSTEM_HEALTH_CHECKLIST.json` · ชุด: `BUNDLE-H01`

## อาการในแอป

| อาการ | ความหมาย | แอปที่มักเจอ |
|-------|----------|--------------|
| `permission-denied` | Firestore rules บล็อก read/write | **van3** หน้ารับงาน, van2 ตะกร้า, van1 ออเดอร์ |
| โหลดค้าง / spinner ไม่จบ | listener error หรือ network | ทุกแอป |
| ข้อมูลไม่อัปเดต real-time | listener หลุด แต่ยัง login | van3 `orders` / `riders` |
| push ไม่มา แต่เปิดแอปเห็นออเดอร์ | Functions/FCM ไม่ใช่ Firestore listener | van3 |

---

## Gate ก่อน/หลัง deploy (อัตโนมัติ)

| ช่วง | สคริpt | บล็อก deploy? | เงื่อนไข |
|------|--------|---------------|----------|
| **Pre-deploy** | `deploy-smoke-test.ps1 -Phase PreDeploy` | **ใช่** — ล้มแล้วไม่ deploy | compile + **emulator บังคับ** (Java 21+) |
| **Post-deploy** | `deploy-smoke-test.ps1 -Phase PostDeploy` | emulator ล้ม = แนะนำ rollback | compile + emulator; **live ไม่บล็อก** |

```powershell
# รัน gate ก่อน deploy เอง (deploy-self เรียกให้อัตโนมัติ)
van2\scripts\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PreDeploy

# หลัง deploy
van2\scripts\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PostDeploy
```

**Live production smoke** (`smoke-test-config.local.json` + ADC) — ถ้าล้มเพราะไม่มี service account ในเครื่อง **ไม่ถือว่า rules พัง** และ **ไม่ rollback** อัตโนมัติ

---

## Checklist ตาม collection (หลัง deploy SHARED Firestore)

### van3 ไรเดอร์ — สำคัญที่สุด

| Collection / Query | หน้าที่ใช้ | Emulator smoke | ทดสอบมือ |
|--------------------|-----------|------------------|----------|
| `orders` `driverId == uid` | งานที่รับแล้ว | ✅ | หน้ารับงานไม่ error |
| `riders/{uid}` | online, FCM | ✅ | เปิด online ได้ |
| `credits/{uid}` | เครดิตก่อนรับงาน | ✅ | กระเป๋า/เครดิตโหลด |
| `payment_config/collection` | เติมเงิน | ✅ | QR เติมเงิน |
| `rider_reviews` | รีวิวจากลูกค้า | ✅ (get) | ตั้งค่า → รีวิว |
| `chats` / `call_sessions` | แชท/โทร | ✅ (แชท) | ส่งข้อความ/โทร |
| FCM / Functions | งานใหม่ popup | — | สร้างออเดer van2 → popup |

### van2 ลูกค้า

| Collection / Query | หน้าที่ใช้ | Emulator smoke | ทดสอบมือ |
|--------------------|-----------|------------------|----------|
| `orders` (customerId) | roadmap / สถานะ | ✅ | ดูออเดอร์ |
| `riders` `onlineReady` | หาไรเดอร์ในตะกร้า | ✅ | สั่งซื้อ COD |
| `products` / `public_shops` | หน้าร้าน | ✅ | เปิด catalog |
| `app_notifications` | แจ้งเตือน | ✅ | tab แจ้งเตือน |
| `payment_config` | PromptPay | ✅ | ชำระเงิน |
| `chats` + messages | แชทร้าน | ✅ | ส่งข้อความ |
| `product_reviews` / `shop_reviews` | รีวิว | ✅ (get) | รีวิวหลังส่ง |
| `admin_support_tickets` | ติดต่อแอดมิน | ✅ create | ตั้งค่า → ติดต่อ |

### van1 ร้านค้า

| Collection / Query | หน้าที่ใช้ | Emulator smoke | ทดสอบมือ |
|--------------------|-----------|------------------|----------|
| `orders` (shopOwnerId) | รายการออเดอร์ | ✅ (get) | หน้าออเดอร์โหลด |
| `app_notifications` van1 | แจ้งออเดอร์ใหม่ | ✅ | มีแจ้งเตือน |
| `shop_operations/{uid}` | เปิด/ปิดร้าน | ✅ | สวิตช์ร้าน |
| `products` (ownerUid) | สินค้า | ✅ (get) | จัดการสินค้า |
| `product_reviews` / `shop_reviews` | รีวิวลูกค้า | ✅ (get) | ตั้งค่า → รีวิว |
| `credits` | กระเป๋าร้าน | ✅ | wallet |
| `admin_support_tickets` | ติดต่อแอดมิน | ✅ create | ตั้งค่า → ติดต่อ |

**ข้อควรรู้:** ออเดอร์ PromptPay ที่ยัง **ไม่ verify** — ร้าน **อ่านไม่ได้** (by design). ถ้ามีออเดอร์แบบนี้ใน query `shopOwnerId` ทั้ง list อาจ error — แอปควรกรองฝั่ง client หรือใช้ query ที่ไม่รวม payment ค้าง

### van4 แอดมิน

| Collection | Emulator smoke | ทดสอบมือ |
|------------|----------------|----------|
| `admin_support_tickets` | ✅ list + update | inbox ติดต่อแอดมิน |
| `orders` / `riders` | ✅ list | dashboard |
| `admins/{email}` | — | login แอดมิน |

---

## ทดสอบมือเร็ว (2–3 นาที หลัง deploy Firestore)

1. **van3** — login → เปิด online → หน้ารับงาน (ไม่ error)
2. **van2** — แจ้งเตือน + ออเดอร์/ตะกร้า
3. **van1** — รายการออเดอร์ร้าน
4. **van4** — ข้อความติดต่อแอดมิน

---

## Rollback Firestore rules

```powershell
van2\scripts\deploy-restore-firestore-rules.ps1
# หรือระบุไฟล์ backup
van2\scripts\deploy-restore-firestore-rules.ps1 -BackupFile "scripts\deploy-backups\firestore-default-....rules"
```

Backup ถูกสร้างอัตโนมัติก่อน deploy firestore (ข้อ 6) ที่ `scripts/deploy-backups/`

---

## เมื่อไหร่ rollback vs ไม่ rollback

| ผลทดสอบ | การตัดสินใจ |
|---------|-------------|
| **Pre-deploy emulator ล้ม** | ไม่ deploy (บล็อกอัตโนมัติ) |
| **Post-deploy emulator ล้ม** | **Rollback ทันที** + smoke van3 |
| **Live smoke ล้ม (ไม่มี ADC)** | **ไม่ rollback** — ใช้ emulator + ทดสอบมือ |
| **แอป van3 permission-denied จริง** | Rollback จาก backup ล่าสุด |
