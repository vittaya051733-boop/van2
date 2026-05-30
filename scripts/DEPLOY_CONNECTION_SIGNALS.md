# สัญญาณการหลุดการเชื่อมต่อ (ข้อ 4)

ใช้หลัง deploy ทุกครั้ง โดยเฉพาะ target **SHARED** (Firestore rules, functions สำคัญ)

## อาการในแอป

| อาการ | ความหมาย | แอปที่มักเจอ |
|-------|----------|--------------|
| `permission-denied` | Firestore rules บล็อก read/write | **van3** หน้ารับงานใหม่, van2 ตะกร้า |
| โหลดค้าง / spinner ไม่จบ | listener error หรือ network | ทุกแอป |
| ข้อมูลไม่อัปเดต real-time | listener หลุด แต่ยัง login | van3 orders/riders |
| push ไม่มา แต่เปิดแอปเห็นออเดอร์ | Functions/FCM ไม่ใช่ Firestore listener | van3 |

## ทดสอบอัตโนมัติ (ข้อ 3)

หลัง deploy SHARED สคริปต์รัน `deploy-smoke-test.ps1` ให้:
- ทดสอบ rules บน emulator (rider orders/riders query)
- ทดสอบ production ถ้ามี `smoke-test-config.local.json`

## ทดสอบมือเพิ่ม (แนะนำ)

1. **van3** → หน้า **รับงานใหม่** (ไม่ error)
2. **van3** → เปิด online
3. **van2** → ดูออเดอร์/ตะกร้า
4. **van1** → ดูออเดอร์ร้าน

## Rollback Firestore rules

```powershell
van2\scripts\deploy-restore-firestore-rules.ps1
# หรือระบุไฟล์ backup
van2\scripts\deploy-restore-firestore-rules.ps1 -BackupFile "scripts\deploy-backups\firestore-default-....rules"
```

Backup ถูกสร้างอัตโนมัติก่อน deploy firestore (ข้อ 6) ที่ `scripts/deploy-backups/`
