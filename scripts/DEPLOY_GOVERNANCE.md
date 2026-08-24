# Van Ecosystem — คู่มือ Deploy ปลอดภัย

> **ทางเข้าเดียว:** `deploy.ps1`  
> Manifest: `deploy-governance.ps1`  
> จุดเสี่ยง: `DEPLOY_RISK_MATRIX.md` | สัญญาณหลุด: `DEPLOY_CONNECTION_SIGNALS.md` | CROSS-WRITE: `VAN_ECOSYSTEM_CROSS_WRITE.md` | Schema: `VAN_ECOSYSTEM_SCHEMA_REGISTRY.md` | Bundle: `deploy-bundles/BUNDLE-CATALOG.th.md`

## ทางเข้าเดียว (แนะนำ)

```powershell
van2\scripts\deploy.ps1 -List
van2\scripts\deploy.ps1 -Bundle BUNDLE-A01 -ShowOnly
van2\scripts\deploy.ps1 -Health
van2\scripts\deploy.ps1 -Ledger
```

**ห้าม** `firebase deploy` ดิบ

## Workflow แนะนำ (ข้อ 1–6)

```powershell
# ข้อ 5 — dry-run ก่อน (ไม่ deploy จริง)
van2\scripts\deploy-plan.ps1 -App van2 -Target firestore -DryRunOnly

# deploy จริง — รวมข้อ 1,2,6 อัตโนมัติ + ข้อ 4 หลัง deploy
van2\scripts\deploy-plan.ps1 -App van2 -Target firestore -Execute `
  -ConfirmDeploy "APPROVE:van2:van-merchant" `
  -ConfirmImpact "SHARED:van1,van2,van3,van4" `
  -FinalAcknowledge "YES I UNDERSTAND"
```

| ข้อ | ทำอะไร | สคริปต์ |
|-----|--------|---------|
| 1 | ดู impact SHARED/SELF + readiness | `deploy-plan.ps1` / `deploy-readiness.ps1` |
| 2 | deploy ทีละ target | `deploy-self.ps1` (ห้าม firebase deploy รวม) |
| 3 | smoke test อัตโนมัติ | **Pre-deploy gate** (บล็อก deploy) + **Post-deploy verify** |
| 3b | emulator ครอบ van1/van2/van3/van4 | `scripts/smoke-test/rules-emulator-test.js` |
| 4 | รู้สัญญาณหลุด | `DEPLOY_CONNECTION_SIGNALS.md` (checklist ตาม collection) |
| 5 | dry-run ก่อน deploy ใหญ่ | `deploy-plan.ps1 -DryRunOnly` |
| 6 | backup ก่อน deploy ทุก target | อัตโนมัติ → `scripts/deploy-backups/sessions/` |
| 7 | **checkpoint ก่อนลบโค้ด** | แจ้งผลกระทบ → รอยืนยัน → ค่อย deploy (ดูด้านล่าง) |

## Checkpoint ก่อนลบโค้ด (ข้อ 7 — บังคับสำหรับ Agent)

ก่อน **ลบ / ย้าย / แทนที่** โค้ดที่อาจเปลี่ยนพฤติกรรม production (native FCM, notification flow, Cloud Functions, Firestore rules, shared filters, intent flags):

### ลำดับที่ถูก

1. **ห้ามลบหรือ deploy ทันที** — สรุปกลับผู้ใช้ก่อนอย่างน้อย:
   - ไฟล์/ฟังก์ชัน/พฤติกรรมที่จะหายไปหรือเปลี่ยน
   - กระทบแอปไหน: van1 / van2 / van3 / van4 — **SHARED หรือ SELF**
   - สถานะหน้าจอที่อาจเปลี่ยน: foreground / background / killed / locked
   - ต้อง deploy อะไรบ้าง (functions ชื่อใด, APK ใหม่ van ไหน, rules)
   - ความเสี่ยงถ้า **ไม่** deploy คู่กัน (เช่น แก้ functions แต่ไม่ build APK)
2. **รอยืนยันจากผู้ใช้** — คำว่า “ลบได้”, “deploy ได้”, หรือคำสั่งชัดเจน
3. **ค่อย deploy** ตาม workflow ข้อ 1–6 ทีละ target

### ตัวอย่างที่ต้องแจ้งก่อนลบ

| การเปลี่ยน | มักกระทบ |
|-----------|----------|
| ลบ `super.onMessageReceived`, overlay fallback, `startActivity` | แจ้งเตือนไม่เด้งเมื่อแอปปิด |
| เปลี่ยน FCM เป็น `notification`+`data` แทน data-only | native handler ไม่ถูกเรียกใน background |
| ลบ `FLAG_ACTIVITY_CLEAR_TOP` / เพิ่ม wake activity | หน้าจอดำ / navigation ผิด |
| แก้ `pushAppNotification`, firestore rules, indexes | van อื่นใน ecosystem |

### Agent

- Cursor rule: `.cursor/rules/van-code-removal-deploy-checkpoint.mdc` (ทุก van repo)
- ถ้าไม่แน่ใจว่ากระทบ SHARED หรือไม่ → ถือว่า **SHARED** จนกว่าจะพิสูจน์จาก `DEPLOY_RISK_MATRIX.md`

## Smoke test อัตโนมัติ (ข้อ 3)

**Pre-deploy (บล็อก deploy ถ้าล้ม):** `deploy-self.ps1` เรียกก่อน firestore deploy อัตโนมัติ  
**Post-deploy:** emulator ล้ม = exit 1 + แนะนำ rollback; **live ล้ม = คำเตือนอย่างเดียว**

```powershell
# Gate ก่อน deploy (deploy-self เรียกให้อัตโนมัติ)
van2\scripts\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PreDeploy

# หลัง deploy
van2\scripts\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PostDeploy
```

ต้องมี **Java 21+** สำหรับ emulator (บังคับ — ไม่ skip ยกเว้น `-AllowSkipEmulatorSmoke` ฉุกเฉิน)

หลัง deploy **firestore / functions** จะรัน:
1. **Rules compile** dry-run
2. **Rules emulator** — van3 rider, van1 shop, van2 customer, van4 admin (+ แชท/แจ้งเตือน/รีวิว/support)
3. **Live production** (ถ้ามี config) — **ไม่บล็อก rollback**

## Rollback

```powershell
# restore จาก step backup ล่าสุด (ไฟล์ local)
van2\scripts\deploy-restore-backup.ps1

# restore แล้ว deploy กลับ
van2\scripts\deploy-restore-backup.ps1 -DeployAfterRestore

# restore firestore shared (legacy)
van2\scripts\deploy-restore-firestore-rules.ps1
van2\scripts\deploy-restore-firestore-rules.ps1 -DeployAfterRestore
```

## Deploy หลาย target (batch)

เมื่อ deploy หลายแอปพร้อมกัน — **สำรองทุก step ก่อน deploy ใดๆ**:

```powershell
# dry-run
van2\scripts\deploy-batch.ps1 -Step van2:firestore,van4:firestore-van4,van4:storage -DryRunOnly

# deploy จริง
van2\scripts\deploy-batch.ps1 -Step van2:firestore,van4:firestore-van4 -Execute `
  -ConfirmDeploy "APPROVE:van2:van-merchant" `
  -ConfirmImpact "SHARED:van1,van2,van3,van4" `
  -FinalAcknowledge "YES I UNDERSTAND"
```

Session backup อยู่ที่ `scripts/deploy-backups/sessions/{timestamp}/manifest.json`

## ตรวจสุขภาพ Ecosystem (รันครั้งเดียว)

```powershell
van2\scripts\ecosystem-health.ps1 -MatrixOnly   # ดูจุดเชื่อมทั้งหมด
van2\scripts\ecosystem-health.ps1               # readiness + smoke + สรุป van/collection ที่น่าจะหลุด
```

รายการจุด: `ECOSYSTEM_HEALTH_CHECKLIST.json` · ชุด `BUNDLE-H01`

## Deploy ตามชุด (Bundle) — โฟกัสเรื่องเดียว

สารบัญ: `scripts/deploy-bundles/BUNDLE-CATALOG.th.md`

```powershell
# ดูรายการชุด + รหัส + หัวข้อ
van2\scripts\deploy-bundle.ps1 -List

# อ่านผลกระทบภาษาไทยก่อน (ไม่ deploy) — AI ต้องทำก่อนเสมอ
van2\scripts\deploy-bundle.ps1 -Bundle BUNDLE-A01 -ShowOnly

# โปรโมชั่น — แก้ rules (SHARED + backup + smoke)
van2\scripts\deploy-bundle.ps1 -Bundle BUNDLE-A01-RULES -DryRunOnly
van2\scripts\deploy-bundle.ps1 -Bundle BUNDLE-A01-RULES -Execute `
  -ConfirmDeploy "APPROVE:van2:van-merchant" `
  -ConfirmImpact "SHARED:van1,van2,van3,van4" `
  -FinalAcknowledge "YES I UNDERSTAND"
```

| รหัส | หัวข้อ |
|------|--------|
| BUNDLE-A01 | โปรโมชั่น/คูปอง (build van4+van2) |
| BUNDLE-A01-RULES | โปรโมชั่น + firestore rules |
| BUNDLE-A02 | pricing_config |
| BUNDLE-S01 | firestore SHARED ทั่วไป |

**กฎ:** ถ้าระบุ Bundle → ห้าม deploy/แก้ไฟล์นอกชุด (ดู `forbidden` + `allowedPaths` ใน JSON)

## คำสั่งอื่น

```powershell
van2\scripts\deploy-readiness.ps1 -App van3 -Target storage
van2\scripts\deploy-self.ps1 -App van3 -Target storage -ConfirmDeploy "APPROVE:van3:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```

## Confirm tokens

- van1–van4: `APPROVE:vanN:van-merchant`
- Final: `YES I UNDERSTAND`
- Firestore: `ConfirmImpact "SHARED:van1,van2,van3,van4"`
