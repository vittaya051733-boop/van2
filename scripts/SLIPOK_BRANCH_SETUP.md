# SlipOK Branch Setup (64492)

Branch ID **64492** ใช้กับ Cloud Function `verifyTopUpSlip` ผ่าน endpoint:

`https://api.slipok.com/api/line/apikey/64492`

## ทำไมต้องตั้ง branch ให้ตรง

เมื่อ branch ตรงบัญชีรับจริง SlipOK จะคืน `data.success === true` พร้อมตรวจผู้รับ/ยอดให้ — ระบบ van จะ **ไม่** override ด้วยชื่อ + 4 ตัวท้ายอีกต่อไป

ถ้า branch ไม่ตรง → มักได้ code **1014** (ผู้รับไม่ตรง) และสลิปจะไม่ผ่าน

## Checklist ใน SlipOK Dashboard

1. เปิด branch **64492**
2. ตั้งบัญชีรับให้ตรงกับ Firestore `payment_config/collection`:
   - **ชื่อผู้รับ:** วิทยา ทนหงษา
   - **PromptPay (บัตรประชาชน):** `1410400168710`
   - **บัญชีธนาคาร (ถ้ามี):** `1643440349`
3. บันทึกแล้วทดสอบสลิปจริง — ต้องได้ `success: true` และ `data.success: true`
4. อย่าใส่ข้อมูลผู้โอน (เช่น ธูปนันท์ / 0447) เป็นผู้รับ

## แหล่งความจริง (source of truth)

| ฟิลด์ | ค่า production |
|--------|----------------|
| `recipientDisplayName` | วิทยา ทนหงษา |
| `promptPayNationalIdOrTaxId` | 1410400168710 |
| `bankAccountNumber` | 1643440349 |

อ่านจาก Firebase Console → Firestore → `payment_config` → `collection`

## หลังตั้ง branch แล้ว

- `verifyTopUpSlip` ยอมรับเฉพาะเมื่อ SlipOK `data.success === true`
- ต้องมี `transRef` และไม่ซ้ำใน collection `slip_trans_refs`
- ยอดสูงสุด **5,000** บาท/ครั้ง, ส่งสลิป **3 ครั้ง/วัน/uid**
- Audit: รูปใน Storage + log ใน `slipok_feedback`

## Deploy function หลังเปลี่ยน logic

```powershell
cd C:\Users\TAM\Desktop\van2\scripts
.\deploy-readiness.ps1 -App van1 -Target functions -FunctionName verifyTopUpSlip
.\deploy-self.ps1 -App van1 -Target functions -FunctionName verifyTopUpSlip -ConfirmDeploy "APPROVE:van1:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```
