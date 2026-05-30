# Van Ecosystem — คู่มือ Deploy ปลอดภัย

> Manifest: `deploy-governance.ps1`  
> จุดเสี่ยง: `DEPLOY_RISK_MATRIX.md` | สัญญาณหลุด: `DEPLOY_CONNECTION_SIGNALS.md`

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
| 3 | smoke test อัตโนมัติหลัง SHARED deploy | `deploy-smoke-test.ps1` (เรียกจาก deploy-self) |
| 4 | รู้สัญญาณหลุด | แสดงอัตโนมัติหลัง deploy สำเร็จ |
| 5 | dry-run ก่อน deploy ใหญ่ | `deploy-plan.ps1 -DryRunOnly` |
| 6 | backup rules ก่อน firestore | อัตโนมัติ → `scripts/deploy-backups/` |

## Smoke test อัตโนมัติ (ข้อ 3)

หลัง deploy **firestore / functions** จะรันอัตโนมัติ:
1. **Rules emulator** — ทดสอบ rider อ่าน `orders` + `riders` (ทุกครั้ง)
2. **Live production** (ถ้ามี config) — อ่าน Firestore จริงด้วย test UID

```powershell
# รันเอง
van2\scripts\deploy-smoke-test.ps1 -AfterTarget firestore

# เปิด live test: copy config แล้วใส่ rider UID
copy van2\scripts\smoke-test-config.local.json.example van2\scripts\smoke-test-config.local.json
# ต้องมี ADC: gcloud auth application-default login
```

## Rollback rules

```powershell
van2\scripts\deploy-restore-firestore-rules.ps1
van2\scripts\deploy-restore-firestore-rules.ps1 -DeployAfterRestore
```

## คำสั่งอื่น

```powershell
van2\scripts\deploy-readiness.ps1 -App van3 -Target storage
van2\scripts\deploy-self.ps1 -App van3 -Target storage -ConfirmDeploy "APPROVE:van3:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```

## Confirm tokens

- van1–van4: `APPROVE:vanN:van-merchant`
- Final: `YES I UNDERSTAND`
- Firestore: `ConfirmImpact "SHARED:van1,van2,van3,van4"`
