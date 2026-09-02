/**
 * One-time backfill: copy branchId from public_shops (or registration) onto orders.
 *
 * Usage (from van2/functions with service account / firebase login):
 *   node ../scripts/backfill-order-branch-id.js [--dry-run] [--limit=500]
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const REGISTRATION_COLLECTIONS = [
  'market_registrations',
  'shop_registrations',
  'restaurant_registrations',
  'pharmacy_registrations',
];

function normalizeBranchId(raw) {
  const value = String(raw || '').trim();
  if (!value) return 'central';
  if (value === 'nonsung') return 'central';
  return value;
}

function branchFromData(data) {
  if (!data) return null;
  const branchId = normalizeBranchId(data.branchId || data.marketId);
  const branchName = String(data.branchName || '').trim() || null;
  return {
    branchId,
    marketId: branchId,
    ...(branchName ? { branchName } : {}),
  };
}

async function resolveShopBranch(db, shopOwnerId, cache) {
  const key = String(shopOwnerId || '').trim();
  if (!key) return { branchId: 'central', marketId: 'central' };
  if (cache.has(key)) return cache.get(key);

  let resolved = null;
  try {
    const pub = await db.collection('public_shops').doc(key).get();
    if (pub.exists) {
      resolved = branchFromData(pub.data());
    }
  } catch (_) {}

  if (!resolved) {
    for (const collection of REGISTRATION_COLLECTIONS) {
      try {
        const snap = await db.collection(collection).doc(key).get();
        if (snap.exists) {
          resolved = branchFromData(snap.data());
          break;
        }
      } catch (_) {}
    }
  }

  const finalFields = resolved || { branchId: 'central', marketId: 'central' };
  cache.set(key, finalFields);
  return finalFields;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const limitArg = process.argv.find((arg) => arg.startsWith('--limit='));
  const limit = limitArg ? Number(limitArg.split('=')[1]) : 1000;

  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const cache = new Map();

  const snapshot = await db.collection('orders').orderBy('createdAt', 'desc').limit(limit).get();
  let updated = 0;
  let skipped = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    if (data.branchId) {
      skipped += 1;
      continue;
    }
    const shopOwnerId = data.shopOwnerId || data.shopId;
    const branchFields = await resolveShopBranch(db, shopOwnerId, cache);
    if (dryRun) {
      console.log(`[dry-run] ${doc.id} -> branchId=${branchFields.branchId}`);
    } else {
      await doc.ref.set(branchFields, { merge: true });
    }
    updated += 1;
  }

  console.log(`Done. scanned=${snapshot.size} updated=${updated} skipped=${skipped} dryRun=${dryRun}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
