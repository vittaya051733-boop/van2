#!/usr/bin/env node

/*
 * Verify migration users -> customer_users for van2.
 *
 * Pass conditions:
 * 1) No customer-shaped docs remain in users (role==customer OR userType==customer)
 * 2) Sample customer_users UIDs must not exist in users
 * 3) Optional: strict mode requires users total == 0
 *
 * Usage:
 *   node verify-users-to-customer-users.js
 *   node verify-users-to-customer-users.js --sample-size=10
 *   node verify-users-to-customer-users.js --sample-uids=uid1,uid2
 *   node verify-users-to-customer-users.js --strict-all-users-zero
 */

const admin = require('firebase-admin');

function parseArgs(argv) {
  const args = {
    sampleSize: 5,
    sampleUids: [],
    strictAllUsersZero: false,
  };

  for (const token of argv.slice(2)) {
    if (token.startsWith('--sample-size=')) {
      const value = Number(token.slice('--sample-size='.length));
      if (Number.isFinite(value) && value > 0) {
        args.sampleSize = Math.floor(value);
      }
      continue;
    }

    if (token.startsWith('--sample-uids=')) {
      const raw = token.slice('--sample-uids='.length);
      args.sampleUids = raw
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean);
      continue;
    }

    if (token === '--strict-all-users-zero') {
      args.strictAllUsersZero = true;
    }
  }

  return args;
}

async function collectLegacyCustomerUserIds(db) {
  const byRole = await db.collection('users').where('role', '==', 'customer').get();
  const byType = await db.collection('users').where('userType', '==', 'customer').get();

  const ids = new Set();
  for (const doc of byRole.docs) ids.add(doc.id);
  for (const doc of byType.docs) ids.add(doc.id);
  return [...ids];
}

async function getSampleCustomerIds(db, sampleSize) {
  const snap = await db.collection('customer_users').limit(sampleSize).get();
  return snap.docs.map((d) => d.id);
}

async function main() {
  const args = parseArgs(process.argv);

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });

  const db = admin.firestore();

  const legacyCustomerUserIds = await collectLegacyCustomerUserIds(db);
  const customerCountSnap = await db.collection('customer_users').count().get();
  const customerCount = customerCountSnap.data().count || 0;

  const sampleIds = args.sampleUids.length > 0
    ? args.sampleUids
    : await getSampleCustomerIds(db, args.sampleSize);

  const sampleResiduals = [];
  for (const uid of sampleIds) {
    const source = await db.collection('users').doc(uid).get();
    if (source.exists) {
      sampleResiduals.push(uid);
    }
  }

  let totalUsers = null;
  if (args.strictAllUsersZero) {
    const usersTotalSnap = await db.collection('users').count().get();
    totalUsers = usersTotalSnap.data().count || 0;
  }

  const passLegacyZero = legacyCustomerUserIds.length === 0;
  const passSamples = sampleResiduals.length === 0;
  const passStrict = totalUsers === null ? true : totalUsers === 0;
  const passed = passLegacyZero && passSamples && passStrict;

  console.log('=== Verify users -> customer_users (van2) ===');
  console.log(`customer_users total: ${customerCount}`);
  console.log(`legacy users customer docs: ${legacyCustomerUserIds.length}`);
  console.log(`sample checked: ${sampleIds.length}`);
  console.log(`sample residual in users: ${sampleResiduals.length}`);
  if (totalUsers !== null) {
    console.log(`users total (strict): ${totalUsers}`);
  }

  if (!passLegacyZero) {
    console.log('Residual customer IDs in users:');
    for (const id of legacyCustomerUserIds.slice(0, 20)) {
      console.log(`- ${id}`);
    }
  }

  if (!passSamples) {
    console.log('Sample residual IDs in users:');
    for (const id of sampleResiduals) {
      console.log(`- ${id}`);
    }
  }

  if (!passed) {
    console.error('VERIFY FAILED');
    process.exitCode = 1;
    return;
  }

  console.log('VERIFY PASSED');
}

main().catch((err) => {
  console.error('VERIFY ERROR:', err);
  process.exitCode = 1;
});
