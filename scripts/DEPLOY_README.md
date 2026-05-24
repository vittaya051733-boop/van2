# Deploy governance (van2 — canonical hub)

Manifest: `scripts/deploy-governance.ps1`

```powershell
scripts/deploy-safe.ps1 -Action help
scripts/sync-firestore-rules.ps1
scripts/deploy-preflight.ps1 -App van2 -Target firestore
```

See: `scripts/DEPLOY_GOVERNANCE.md`
