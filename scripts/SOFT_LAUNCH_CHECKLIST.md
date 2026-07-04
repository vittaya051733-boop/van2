# Van Ecosystem — Soft Launch Checklist

ใช้ก่อนเปิดระบบกับผู้ใช้จริงใน 1 พื้นที่ (pilot)

## Non Sung 90 วัน (ตลาดโนนสูง)

ชุดปฏิบัติการเต็ม: `scripts\nonsung-launch\README.md`

- [ ] `scripts\nonsung-launch\nonsung-flow-test.ps1`
- [ ] `scripts\nonsung-launch\seed-nonsung-launch.ps1` (โปร NONSUNG50 + pricing/settlement)
- [ ] กรอก `nonsung-shop-survey.csv` (50) + `nonsung-rider-registry.csv` (8)
- [ ] LINE กลุ่มตาม `nonsung-line-groups.md`
- [ ] รายวัน: `nonsung-ops-daily.ps1` | รายสัปดาห์: `nonsung-kpi-weekly.csv`

## ก่อนเปิด (เทคนิค)

- [ ] รัน `scripts\deploy-smoke-test.ps1 -AfterTarget firestore -Phase PreDeploy` ผ่าน
- [ ] รัน rules + order lifecycle E2E: `cd scripts\smoke-test` แล้ว `firebase emulators:exec --project van-smoke-rules-test --only firestore "node rules-emulator-test.js"`
- [ ] ตรวจ Firebase Console: App Check, Auth providers, FCM ทำงาน
- [ ] รัน pilot test อัตโนมัติ: `scripts\soft-launch-pilot-test.ps1`
- [ ] เปิด Crashlytics ตาม `scripts\CRASHLYTICS_SETUP.md`
- [ ] ส่งสัญญาณทดสอบ: `scripts\soft-launch-pilot-test.ps1 -SendObservabilityPing -App van2`
- [ ] ตรวจ Crashlytics + Analytics รับ event `app_start` / `pilot_observability_verify` จาก van1–van4
- [ ] ทดสอบ flow จริง 1 รอบ: ลูกค้าสั่ง → ร้านรับ → ไรเดอร์ส่ง → แอดมินเห็นออเดอร์

## ก่อนเปิด (ปฏิบัติการ)

- [ ] มีไรเดอร์ออนไลน์อย่างน้อย 2 คนในพื้นที่ pilot
- [ ] มีร้าน active อย่างน้อย 3 ร้าน พร้อมพิกัด
- [ ] ตั้งค่า `payment_config/collection` และบัญชีรับเงิน PromptPay
- [ ] แอดมินทดสอบ CSV payout + settlement fee config
- [ ] ช่องทาง support (admin_support_tickets) มีคนตอบภายใน 30 นาที

## วันเปิด (รายวัน)

- [ ] 09:00 — ตรวจไรเดอร์ออนไลน์ + ร้าน pause ออเดอร์
- [ ] 12:00 / 18:00 — ตรวจออเดอร์ค้าง `awaiting_rider` / `preparing`
- [ ] 18:00 — ส่งออก CSV ออเดอร์ (van4) และตรวจ refund queue
- [ ] ก่อน deploy — อ่าน `DEPLOY_GOVERNANCE.md` + backup rules อัตโนมัติ

## สัญญาณเตือน (หยุดรับออเดาร์เพิ่ม)

- ออเดอร์ `awaiting_rider` > 15% ของออเดอร์วันนั้น
- permission-denied ใน van3 logs (rules พัง)
- สลิป verify ล้มต่อเนื่อง > 5 ครั้ง/ชม.
- Crashlytics fatal spike หลัง deploy

## Rollback

```powershell
van2\scripts\deploy-restore-firestore-rules.ps1 -DeployAfterRestore
```
