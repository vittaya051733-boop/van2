# Omise Withdraw Setup (ก่อน deploy)

## Checklist

1. **Omise Dashboard** → Settings → เปิด **Transfer / Payout** (live mode)
2. ตรวจ **Omise balance** ≥ ยอด float ที่ต้องจ่ายไรเดอร์ + ร้านค้า
3. **Webhooks** → endpoint เดิม `omiseWebhook` → เพิ่ม events:
   - `transfer.create`
   - `transfer.send`
   - `transfer.paid`
   - `transfer.failed`
4. Sandbox test: สร้าง recipient + transfer ขั้นต่ำ 30 บาท

## Functions ที่ deploy (van2)

```powershell
cd C:\Users\TAM\Desktop\van2
scripts\deploy-readiness.ps1 -App van2 -Target functions
scripts\deploy-self.ps1 -App van2 -Target functions -FunctionName requestOmiseWithdraw ...
scripts\deploy-self.ps1 -App van2 -Target functions -FunctionName getWithdrawableBalance ...
scripts\deploy-self.ps1 -App van2 -Target functions -FunctionName omiseWebhook ...
```

## Secrets

ใช้ `OMISE_SECRET_KEY` และ `OMISE_WEBHOOK_SECRET` เดิมจาก charge flow
