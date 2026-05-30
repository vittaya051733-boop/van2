# Van Ecosystem — จุดเสี่ยง Deploy และการแยกทรัพยากร

> อ่านคู่กับ `DEPLOY_GOVERNANCE.md` ก่อน deploy ทุกครั้ง  
> Manifest: `deploy-governance.ps1`

## Firebase แชร์กัน — แยกได้แค่ไหน?

Project เดียว: **`van-merchant`**

| ทรัพยากร | แชร์/แยก | van1 | van2 | van3 | van4 | หมายเหตุ |
|----------|----------|------|------|------|------|----------|
| Firestore DB `(default)` | **แชร์ทั้ง 4 แอป** | อ่าน/เขียน | canonical rules | อ่าน/เขียน | อ่าน (admin) | **deploy rules กระทบทุกแอปทันที** |
| Firestore DB `van4` | **แยก** | — | — | — | เจ้าของ | deny-all admin DB |
| Firebase Auth | **แชร์** | ✓ | ✓ | ✓ | ✓ | เปลี่ยน provider/config กระทบทุกแอป |
| Cloud Functions van1 | **แยก codebase** | deploy | — | — | — | deploy ทีละชื่อ |
| Cloud Functions van2 | **แยก codebase** | — | deploy | — | — | `pushAppNotification` สำคัญต่อไรเดอร์ |
| Storage bucket | **แยก target** | van1 | van2 | van3 | van4 | deploy แยกได้ 100% |
| Hosting site | **แยก target** | van1 | van2 | van3 | van4 | deploy แยกได้ 100% |
| FCM / App Check | **แชร์ project** | ✓ | ✓ | ✓ | ✓ | เปลี่ยน config กระทบ push ทุกแอป |

**สรุป:** แยก **deploy** ได้ทุก target ยกเว้น Firestore `(default)` rules และ Auth/FCM ระดับ project — ต้อง deploy แยกทีละ target ผ่าน `deploy-self.ps1` / `deploy-safe.ps1` **ห้ามรวม**

---

## จุดเสี่ยงต่อแอป (ถ้า deploy ผิด = หลุดการเชื่อมต่อ)

### van1 — ร้าน (Merchant)

| ความเสี่ยง | ทรัพยากร | กระทบใคร | อาการ |
|-----------|----------|----------|-------|
| Deploy Firestore rules ผิดเวอร์ชัน | SHARED | van1,2,3,4 | permission-denied ทุก listener |
| Deploy functions ทั้ง codebase | SELF van1 | van1 + order flow | `onOrderStatusUpdate`, `checkPreparingOrders` พัง |
| Deploy storage rules ผิด bucket | SELF van1 | van1 | อัปโหลดรูป/สลิปล้ม |
| รวม deploy firestore+storage+hosting | MIXED | **van3 ไรเดอร์หลุด** | rules เปลี่ยนขณะ rider online |

**Deploy ได้:** storage SELF, hosting SELF, functions ทีละชื่อ  
**Deploy ไม่ได้ตรง:** Firestore default (delegate van2)

---

### van2 — ลูกค้า (Customer) — Canonical hub

| ความเสี่ยง | ทรัพยากร | กระทบใคร | อาการ |
|-----------|----------|----------|-------|
| Deploy `firestore.rules` | **SHARED** | **ทุกแอป** | ไรเดอร์หลุด listener `orders`, `riders` |
| Deploy `pushAppNotification` | SELF van2 | van3 | ไรเดอร์ไม่ได้รับ job push |
| Deploy OTP/call functions | SELF van2 | van2, van3 | login/call ล้ม |
| `firebase deploy --only firestore,functions` | MIXED | ทุกแอป | รวม shared + self พร้อมกัน |

**Real-time ที่พึ่ง Firestore:** ตะกร้า, catalog, order status, chat notifications

---

### van3 — ไรเดอร์ (Rider) — **Sensitive ที่สุด**

| Listener / Service | Collection | ถ้า rules พัง |
|--------------------|------------|----------------|
| `RiderOrdersService` | `orders` (driverId) | ไม่เห็นออเดอร์ |
| `GlobalOrderAlertService` | stream เดียวกัน | ไม่มี popup job |
| `home_screen` | `riders/{uid}` | online/offline หลุด |
| `FcmTokenSyncService` | `riders/{uid}` | push ไม่มา |

| ความเสี่ยง | ทรัพยากร | อาการ |
|-----------|----------|-------|
| Deploy Firestore จาก van3 | SHARED (blocked) | ถ้าฝ่าฝืน → ทุก rider offline |
| Deploy functions จาก van3 | blocked | ไม่มี codebase |
| Deploy storage/hosting | SELF | ปลอดภัย — ไม่กระทบ connection |

**van3 deploy ได้แค่:** `storage` + `hosting` (SELF เท่านั้น)

---

### van4 — Admin

| ความเสี่ยง | ทรัพยากร | กระทบ |
|-----------|----------|-------|
| Deploy Firestore default | SHARED (blocked) | ทุกแอป |
| Deploy Firestore DB `van4` | SELF van4 | admin DB เท่านั้น |
| Deploy storage/hosting | SELF van4 | web admin |

---

## คำสั่งที่ห้ามใช้ (ทุกแอป / ทุก AI)

```powershell
# ห้าม — deploy รวมหลาย service
firebase deploy --only firestore,functions,storage
firebase deploy --only firestore
firebase deploy --only functions
firebase deploy                                    # ใช้ firebase.json ทั้งก้อน

# ห้าม — สคริปต์ legacy
scripts/deploy-van-merchant-rules.ps1
deploy-auto.ps1                                    # blocked — ใช้ deploy-self.ps1
```

---

## คำสั่งที่ถูกต้อง (แยกทีละ target)

```powershell
# 1) อ่านกฎ + ตรวจ readiness (ทุกครั้ง)
van2\scripts\deploy-readiness.ps1 -App van3

# 2) Deploy แยกทีละอย่าง
van2\scripts\deploy-self.ps1 -App van3 -Target storage -ConfirmDeploy "APPROVE:van3:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"

van2\scripts\deploy-self.ps1 -App van2 -Target firestore -ConfirmDeploy "APPROVE:van2:van-merchant" -ConfirmImpact "SHARED:van1,van2,van3,van4" -FinalAcknowledge "YES I UNDERSTAND"

van2\scripts\deploy-self.ps1 -App van2 -Target functions -FunctionName pushAppNotification -ConfirmDeploy "APPROVE:van2:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```

---

## Smoke test หลัง deploy SHARED resources

1. van3 login → เปิด online → ตรวจ `riders/{uid}` มี `onlineReady`, `fcmToken`
2. สร้างออเดอร์ van2 → ไรเดอร์ได้ popup
3. van1 ดู order list โหลดได้
4. van4 admin เปิด dashboard ได้

---

## ลำดับ deploy ที่ปลอดภัย (release ทั้งระบบ)

1. `sync-firestore-rules.ps1` (ถ้าแก้ rules)
2. `deploy-self -Target firestore` (van2) — **นอก peak hour**
3. Smoke test ไรเดอร์ทันที
4. `deploy-self -Target functions` ทีละชื่อ (van1 แล้ว van2)
5. `deploy-self -Target storage` แยกแต่ละแอป
6. `deploy-self -Target hosting` แยกแต่ละแอป

**ห้ามข้ามขั้นตอน 3** หลัง deploy Firestore rules
