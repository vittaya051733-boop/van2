# van2 Customer — Agent Instructions

## Before ANY Firebase deploy

1. Read `scripts\DEPLOY_GOVERNANCE.md`
2. Read `scripts\DEPLOY_RISK_MATRIX.md`
3. Run `scripts\deploy-readiness.ps1 -App van2 -Target <target>`
4. Deploy ONE target: `scripts\deploy-self.ps1 -App van2 -Target <target> ...`

## Critical

Firestore `(default)` rules are **SHARED** with van1, van3 (rider), van4.  
After SHARED deploy → smoke test van3 rider immediately.

## Never

- `firebase deploy --only firestore,functions,storage`
- `deploy-auto.ps1` (blocked)
- Deploy all functions at once

## Allowed targets

`firestore`, `storage`, `hosting`, `functions` (explicit names)

## Local Flutter dev (emulator)

1. Start once: `scripts\flutter-run-dev.ps1` (uses `flutter run --machine`, enables reload channel)
2. After **any** `lib/` or `test/` edit: run `scripts\flutter-hot-reload.ps1`
3. Agent: always run hot reload script after completing van2 UI/logic fixes when emulator dev session is expected
