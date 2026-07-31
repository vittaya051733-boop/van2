# Omise setup (van2)

## Firebase Secrets

```powershell
cd C:\Users\TAM\Desktop\van2\functions
firebase functions:secrets:set OMISE_SECRET_KEY
firebase functions:secrets:set OMISE_PUBLIC_KEY
```

- `OMISE_SECRET_KEY` — `skey_test_...` or `skey_live_...` (charges, customers)
- `OMISE_PUBLIC_KEY` — `pkey_test_...` or `pkey_live_...` (**must** be Public Key from the same Omise account + mode as secret)
- Card tokenization uses **`https://vault.omise.co/tokens`** (not `api.omise.co`)
- `OMISE_WEBHOOK_SECRET` — Base64 webhook secret from Omise Dashboard → Webhooks Settings

```powershell
cd C:\Users\TAM\Desktop\van2\functions
firebase functions:secrets:set OMISE_WEBHOOK_SECRET
```

During secret rotation, set both secrets comma-separated (current,expiring):

```powershell
firebase functions:secrets:set OMISE_WEBHOOK_SECRET
# paste: NEW_SECRET,OLD_SECRET
```

## Omise Dashboard

1. **Webhook URL** (after deploy `omiseWebhook`):
   `https://asia-southeast1-van-merchant.cloudfunctions.net/omiseWebhook`
2. **Webhook secret** — copy from Webhooks Settings into `OMISE_WEBHOOK_SECRET`
3. Events: `charge.complete`, `charge.create` (optional)
4. Enable Thailand payment methods: PromptPay, Cards, Mobile Banking, TrueMoney Wallet

`omiseWebhook` verifies `Omise-Signature` + `Omise-Signature-Timestamp` using HMAC-SHA256
(`<timestamp>.<raw_body>` with Base64-decoded secret).

## Deploy (via van2 governance scripts)

```powershell
cd C:\Users\TAM\Desktop\van2\scripts
..\..\van2\..\van2\scripts\deploy-readiness.ps1 -App van2 -Target functions
# Deploy each new function name individually per DEPLOY_GOVERNANCE.md:
# createOmisePaymentSession, getOmisePaymentSession, createOmiseCardToken, omiseWebhook
# syncFloatAdvanceOnOrderDelivered, promoteMerchantPayoutsScheduled, reconcileOmiseSettleScheduled
```

## Firestore (SHARED)

Deploy firestore rules from van2 after adding `payment_sessions` + `float_advances` rules.

## Smoke test

1. van2 cart → ชำระ → PromptPay (test mode)
2. van2 travel → ชำระ → COD still works
3. van3 rider app still receives orders
4. van1 merchant top-up slip unchanged
