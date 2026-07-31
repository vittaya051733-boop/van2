#!/usr/bin/env node
/**
 * Simulate van2 browse load against production Firestore (admin SDK).
 *
 * Usage:
 *   cd functions
 *   node ../scripts/load-test/simulate-browse-load.mjs --clients 3000 --rounds 3
 *   node ../scripts/load-test/simulate-browse-load.mjs --clients 5000 --rounds 5
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or gcloud application-default login.
 */

import { parseArgs } from 'node:util';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(scriptDir, '../../functions/package.json'));
const admin = require('firebase-admin');

const { values } = parseArgs({
  options: {
    clients: { type: 'string', default: '1000' },
    rounds: { type: 'string', default: '3' },
    concurrency: { type: 'string', default: '100' },
  },
});

const clientCount = Math.max(1, Number.parseInt(values.clients, 10) || 1000);
const rounds = Math.max(1, Number.parseInt(values.rounds, 10) || 3);
const concurrency = Math.max(1, Number.parseInt(values.concurrency, 10) || 100);

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function simulateBrowseClient(clientId) {
  const started = performance.now();
  await Promise.all([
    db.doc('system/rider_availability').get(),
    db.collection('products').where('isActive', '==', true).limit(24).get(),
    db.collection('public_shops').limit(20).get(),
  ]);
  return performance.now() - started;
}

async function runRound(roundIndex) {
  const latencies = [];
  let cursor = 0;

  async function worker() {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= clientCount) {
        return;
      }
      latencies.push(await simulateBrowseClient(index));
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, clientCount) }, () => worker());
  const roundStarted = performance.now();
  await Promise.all(workers);
  const roundMs = performance.now() - roundStarted;

  latencies.sort((a, b) => a - b);
  const p50 = latencies[Math.floor(latencies.length * 0.5)] ?? 0;
  const p95 = latencies[Math.floor(latencies.length * 0.95)] ?? 0;
  const p99 = latencies[Math.floor(latencies.length * 0.99)] ?? 0;

  console.log(
    JSON.stringify({
      round: roundIndex + 1,
      simulatedClients: clientCount,
      concurrency,
      roundDurationMs: Math.round(roundMs),
      latencyMs: {
        p50: Math.round(p50),
        p95: Math.round(p95),
        p99: Math.round(p99),
      },
    }),
  );
}

console.log(
  JSON.stringify({
    event: 'load_test_start',
    clients: clientCount,
    rounds,
    concurrency,
    readsPerClient: 3,
  }),
);

for (let round = 0; round < rounds; round += 1) {
  await runRound(round);
}

console.log(JSON.stringify({ event: 'load_test_complete' }));
