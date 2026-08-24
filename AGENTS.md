# van2 Customer — Agent Instructions

## Before ANY Firebase deploy

1. Read `scripts\DEPLOY_GOVERNANCE.md` + `scripts\deploy-bundles\BUNDLE-CATALOG.th.md`
2. Prefer single entry: `scripts\deploy.ps1 -Bundle BUNDLE-xxx -ShowOnly` then `-Execute`
3. Or: `scripts\deploy.ps1 -App van2 -Target <target> ...`
4. After SHARED: `scripts\deploy.ps1 -Health` (or at least smoke van3)
5. Never: raw `firebase deploy`

## Before removing production code

See `DEPLOY_GOVERNANCE.md` § **Checkpoint ก่อนลบโค้ด**: report impact (which vans, SHARED/SELF, deploy targets) and wait for user confirmation before delete + deploy.

## Schema / CROSS-WRITE

Expand-only: `VAN_ECOSYSTEM_SCHEMA_REGISTRY.md` — add fields first, delete later after consumers deploy.

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
