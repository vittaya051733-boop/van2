# Verify Commands (van2)

## Syntax check scripts

```bash
node --check migrate-users-to-customer-users.js
node --check verify-users-to-customer-users.js
```

## Verify หลัง migrate

```bash
node verify-users-to-customer-users.js --sample-size=10
```

## Verify แบบ strict ว่า users ต้องเหลือ 0 ทั้งคอลเลกชัน

```bash
node verify-users-to-customer-users.js --strict-all-users-zero
```

## Verify เฉพาะ sample uid

```bash
node verify-users-to-customer-users.js --sample-uids=<uid1>,<uid2>,<uid3>
```
