# Deploy (van2 Customer — canonical hub)

**อ่านก่อน deploy ทุกครั้ง:**
- `scripts\DEPLOY_GOVERNANCE.md`
- `scripts\DEPLOY_RISK_MATRIX.md`

```powershell
scripts\deploy-readiness.ps1 -App van2 -Target firestore
scripts\deploy-self.ps1 -App van2 -Target firestore `
  -ConfirmDeploy "APPROVE:van2:van-merchant" `
  -ConfirmImpact "SHARED:van1,van2,van3,van4" `
  -FinalAcknowledge "YES I UNDERSTAND"
```

Manifest: `scripts\deploy-governance.ps1`
