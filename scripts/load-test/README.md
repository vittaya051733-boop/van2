# van2 browse load test

Simulates concurrent van2 home/browse reads before go-live.

## What it measures

Each simulated client performs 3 reads (same pattern as scaled van2 browse):

1. `system/rider_availability` (single doc)
2. `products where isActive==true limit 24`
3. `public_shops limit 20`

## Prerequisites

- Firebase Admin credentials (`gcloud auth application-default login` or service account)
- Node 20+

## Run

```powershell
cd C:\Users\TAM\Desktop\van2\functions

# Warm path — 3k simulated clients
node ..\scripts\load-test\simulate-browse-load.mjs --clients 3000 --rounds 3 --concurrency 150

# Target — 5k simulated clients
node ..\scripts\load-test\simulate-browse-load.mjs --clients 5000 --rounds 5 --concurrency 200
```

## Interpret results

- **p95 latency under ~800ms** per client round-trip: healthy for catalog browse at target load
- **p95 above 2s**: review Firestore indexes, catalog cache TTL, or reduce concurrent poll frequency
- Run after deploying `system/rider_availability` rules + `refreshRiderAvailabilityPoolScheduled`

## Notes

- Admin SDK bypasses security rules — this tests Firestore/backend capacity, not client auth paths
- For callable burst testing (checkout / SlipOK), run smaller concurrent batches against staging only
