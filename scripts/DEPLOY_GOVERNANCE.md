# Van Ecosystem — คู่มือ Deploy ปลอดภัย

> Manifest กลาง: `deploy-governance.ps1` (แก้ ownership ที่นี่ที่เดียว)

## โครงสร้าง

```
Desktop/
  van1/my-flutter/   ร้าน      — functions van1, storage SELF, Firestore → delegate van2
  van2/              ลูกค้า    — Firestore canonical, functions van2, storage SELF
  van3/              ไรเดอร์   — storage/hosting SELF, Firestore → delegate van2, ไม่มี functions
  van4/              admin     — storage/hosting SELF, optional DB van4, ไม่มี functions
```

Manifest กลาง: `deploy-governance.ps1` | Bootstrap: `deploy-governance-import.ps1`

## สิทธิ์ deploy ต่อแอป

| แอป | Firestore default | Firestore DB van4 | Functions | Storage | Hosting |
|-----|-------------------|-------------------|-----------|---------|---------|
| van1 | delegate van2 | — | van1 codebase | SELF | SELF |
| van2 | **canonical** | — | van2 codebase | SELF | SELF |
| van3 | delegate van2 | — | blocked | SELF | SELF |
| van4 | delegate van2 (runtime) | SELF optional | blocked | SELF | SELF |

Project Firebase เดียว: **van-merchant**

## กฎ 5 ข้อ

| # | กฎ |
|---|-----|
| 1 | แก้ Firestore rules ที่ `van2/firestore.rules` เท่านั้น |
| 2 | รัน `sync-firestore-rules.ps1` ก่อน deploy ทุกครั้ง |
| 3 | Deploy Firestore ผ่าน `deploy-firestore-isolated.ps1` จาก **van2** (van1/van3 delegate มา) |
| 4 | Deploy Functions ทีละชื่อ จากเจ้าของ codebase เท่านั้น |
| 5 | ห้าม `deploy-van-merchant-rules.ps1` และ `firebase deploy --only firestore/functions` แบบไม่มี guard |

## คำสั่งที่ใช้ได้

| งาน | คำสั่ง |
|-----|--------|
| ดูกฎทั้งหมด | `deploy-safe.ps1 -Action help` |
| Sync rules | `sync-firestore-rules.ps1` |
| Preflight | `deploy-preflight.ps1 -App van2 -Target firestore` |
| Deploy rules | `deploy-safe.ps1 -Action firestore -App van2 -ConfirmDeploy ... -FinalAcknowledge "YES I UNDERSTAND"` |
| Deploy function | `deploy-safe.ps1 -Action functions -App van2 -FunctionName pushAppNotification -ConfirmDeploy ...` |

## Confirm tokens

- van1: `APPROVE:van1:van-merchant`
- van2: `APPROVE:van2:van-merchant`
- van3: `APPROVE:van3:van-merchant`
- van4: `APPROVE:van4:van-merchant`
- Final: `YES I UNDERSTAND`
- Firestore impact: `SHARED:van1,van2,van3,van4`

## Function ownership

ดูรายชื่อใน `deploy-governance.ps1` → `FunctionOwnershipVan1` / `FunctionOwnershipVan2`

Deploy ข้าม codebase จะถูก **block อัตโนมัติ**
