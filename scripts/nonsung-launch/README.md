# Non Sung 90-Day Soft Launch — Ops Kit

ชุดเครื่องมือปฏิบัติการสำหรับเปิดตลาดโนนสูง อุดรธานี (ไม่แก้ไฟล์แผนใน `.cursor/plans/`)

## โซนเป้าหมาย (Phase 1)

| พารามิเตอร์ | ค่า |
|------------|-----|
| ศูนย์กลาง | ตลาดโนนสูง |
| พิกัด seed | 17.271°N, 102.638°E |
| รัศมี geo คูปอง | 8,000 m (ปรับใน seed ได้) |
| Peak | 07:00–10:00, 16:00–20:00 |

## เริ่มต้น (วัน 1–14)

```powershell
cd C:\Users\TAM\Desktop\van2\scripts\nonsung-launch

# 1) Pilot + Crashlytics + E2E (จาก van2/scripts)
..\soft-launch-pilot-test.ps1 -SkipEmulator   # หรือไม่ใส่ -SkipEmulator ถ้า Java 21+
..\nonsung-launch\nonsung-flow-test.ps1

# 2) กรอกรายชื่อร้าน/ไรเดอร์
#    nonsung-shop-survey.csv (เป้า 50)
#    nonsung-rider-registry.csv (เป้า 8–10)

# 3) Seed โปร + config (ต้องมี ADC: gcloud auth application-default login)
.\seed-nonsung-launch.ps1 -DryRun
.\seed-nonsung-launch.ps1 -ConfirmSeed "APPROVE:nonsung:van-merchant"
```

## รายวัน (วัน 15+)

```powershell
.\nonsung-ops-daily.ps1              # checklist + snapshot (ถ้ามี ADC)
.\nonsung-ops-daily.ps1 -SnapshotOnly
```

## ไฟล์ตาม Phase

| Phase | วัน | ไฟล์ |
|-------|-----|------|
| Prep | 1–14 | `nonsung-flow-test.ps1`, survey CSV, `seed-nonsung-launch-config.js` |
| Soft launch | 15–45 | `NONSUNG50` (seed), `nonsung-poster-brief.md`, `nonsung-kpi-weekly.csv` |
| Expand | 46–75 | `nonsung-college-campaign.md`, ops snapshot |
| Review | 76–90 | `nonsung-playbook.md`, `nonsung-day90-review.md`, `nonsung-unit-economics.csv` |

## LINE กลุ่ม (สร้างด้วยมือ)

ดู `nonsung-line-groups.md`

## Deploy / Firebase

- Firestore rules → `van2\scripts\deploy-plan.ps1` เท่านั้น
- Seed config → รัน `seed-nonsung-launch.ps1` (เขียน Firestore โดยตรง ไม่ใช่ deploy rules)
- อย่าใช้ `firebase deploy` แบบรวม

## van4 ที่ต้องตรวจหลัง seed

- โปร `nonsung_launch_banner` + คูปอง `NONSUNG50`
- `pricing_config/global` — ค่าส่งโซนโนนสูง
- `platform_config/settlement` — GP เปิดตัว
- `payment_config/collection` — ใส่ PromptPay จริงก่อนรับเงินลูกค้า
