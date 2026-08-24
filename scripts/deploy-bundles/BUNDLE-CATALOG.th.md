# สารบัญ Deploy Bundle (van-merchant) — ครบเฟส 1–4

> **ทางเข้าเดียว:** `van2\scripts\deploy.ps1`  
> ถ้าระบุ Bundle → ทำเฉพาะเรื่องในชุด · ห้ามแตะ `forbidden`  
> ก่อน Execute: `-ShowOnly` (ผลกระทบไทย) · backup อัตโนมัติ · ledger บันทึก

## คำสั่งหลัก

```powershell
van2\scripts\deploy.ps1 -List
van2\scripts\deploy.ps1 -Bundle BUNDLE-A01 -ShowOnly
van2\scripts\deploy.ps1 -Bundle BUNDLE-S01 -DryRunOnly
van2\scripts\deploy.ps1 -Bundle BUNDLE-ST3 -Execute -ConfirmDeploy "อนุมัติ:van3:van-merchant" -FinalAcknowledge "ฉันเข้าใจแล้ว"
van2\scripts\deploy.ps1 -Health
van2\scripts\deploy.ps1 -Health -MatrixOnly
van2\scripts\deploy.ps1 -Ledger
```

---

## ตารางชุดทั้งหมด

| รหัส | หัวข้อ | Scope | Firebase? |
|------|--------|-------|-----------|
| **A01** | โปรโมชั่น/คูปอง | CROSS-WRITE | build |
| **A01-RULES** | โปร + firestore rules | SHARED | van2:firestore |
| **A02** | pricing_config | CROSS-WRITE | build |
| **B01** | แจ้งเตือน/ประกาศ | CROSS-WRITE | build |
| **C01** | catalog/สินค้า/ร้าน | CROSS-WRITE | build |
| **D01** | ออเดอร์/settlement/wallet | CROSS-WRITE | build (+ F01 ถ้า CF) |
| **F01** | Functions van2 (push) | SELF | van2:functions:pushAppNotification |
| **F02** | Functions van1 | SELF | van1:functions:onOrderStatusUpdate |
| **S01** | Firestore SHARED ทั่วไป | SHARED | van2:firestore |
| **ST1–ST4** | Storage van1/2/3/4 | SELF | vanN:storage |
| **HOST** | Hosting คู่มือ | SELF | ใช้ deploy.ps1 -App -Target hosting |
| **H01** | ตรวจสุขภาพ Ecosystem | ตรวจอย่างเดียว | ไม่ deploy |

---

## เอกสารคู่กัน (เฟส 3–4)

| ไฟล์ | หน้าที่ |
|------|--------|
| `ECOSYSTEM_HEALTH_CHECKLIST.json` | จุดเชื่อมทั้งหมด |
| `ecosystem-health.ps1` | รันครั้งเดียว + สถานะรายจุด |
| `VAN_ECOSYSTEM_SCHEMA_REGISTRY.md` | field contract / expand-only |
| `VAN_ECOSYSTEM_CROSS_WRITE.md` | van4 เขียน → ใครอ่าน |
| `deploy-backups/LEDGER.jsonl` | ประวัติ deploy/health |

## กฎ Expand-only

เพิ่ม field ก่อน → migrate consumer → ค่อยลบของเก่า (PR แยก)

## สำหรับ AI

1. ใช้ `deploy.ps1` เท่านั้น — ห้าม `firebase deploy` ดิบ  
2. เลือก Bundle จากตาราง → `-ShowOnly` ก่อน  
3. ห้ามนอก `allowedPaths` / ใน `forbidden`  
4. หลัง SHARED → `deploy.ps1 -Health` หรืออย่างน้อย smoke van3  
5. Schema ข้ามแอป → อัปเดต `VAN_ECOSYSTEM_SCHEMA_REGISTRY.md`
