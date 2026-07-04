/**
 * Daily ops snapshot for Non Sung launch (production read via Admin SDK).
 * Requires ADC: gcloud auth application-default login
 */
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const admin = require('../../functions/node_modules/firebase-admin');
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'van-merchant';

const STUCK_STATUSES = ['awaiting_rider', 'preparing', 'accepted'];

function startOfTodayBangkok() {
  const now = new Date();
  const utc = now.getTime() + now.getTimezoneOffset() * 60000;
  const bangkok = new Date(utc + 7 * 3600000);
  bangkok.setHours(0, 0, 0, 0);
  const backUtc = bangkok.getTime() - 7 * 3600000;
  return admin.firestore.Timestamp.fromDate(new Date(backUtc));
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  const db = admin.firestore();
  const since = startOfTodayBangkok();

  console.log(`Non Sung ops snapshot — ${PROJECT_ID}`);
  console.log(`Since (Bangkok midnight): ${since.toDate().toISOString()}`);

  const ordersSnap = await db
    .collection('orders')
    .where('createdAt', '>=', since)
    .get();

  const byStatus = {};
  let gmv = 0;
  for (const doc of ordersSnap.docs) {
    const d = doc.data();
    const status = String(d.status || 'unknown');
    byStatus[status] = (byStatus[status] || 0) + 1;
    const total = Number(d.grandTotal ?? d.total ?? 0);
    if (!Number.isNaN(total)) gmv += total;
  }

  const stuck = ordersSnap.docs.filter((doc) =>
    STUCK_STATUSES.includes(String(doc.data().status || '')),
  );

  const ridersSnap = await db.collection('riders').get();
  let onlineReady = 0;
  let approved = 0;
  for (const doc of ridersSnap.docs) {
    const d = doc.data();
    if (d.approved === true || d.status === 'approved') approved += 1;
    if (d.onlineReady === true) onlineReady += 1;
  }

  const launchDoc = await db.collection('launch_config').doc('nonsung_90d').get();
  const phase = launchDoc.exists ? launchDoc.data()?.phase : 'unknown';

  console.log('');
  console.log('--- Orders today ---');
  console.log(`Total: ${ordersSnap.size}`);
  console.log(`GMV estimate: ${gmv.toFixed(0)} THB`);
  console.log('By status:', JSON.stringify(byStatus, null, 0));
  console.log(`Stuck (awaiting_rider/preparing/accepted): ${stuck.length}`);
  if (stuck.length > 0 && stuck.length <= 10) {
    for (const doc of stuck) {
      const d = doc.data();
      console.log(`  - ${doc.id} status=${d.status} shop=${d.shopName || d.shopId}`);
    }
  }

  console.log('');
  console.log('--- Riders ---');
  console.log(`Registered docs: ${ridersSnap.size}`);
  console.log(`Approved (heuristic): ${approved}`);
  console.log(`onlineReady now: ${onlineReady}`);

  const orderCount = ordersSnap.size;
  const stuckPct = orderCount > 0 ? (stuck.filter((d) => d.data().status === 'awaiting_rider').length / orderCount) * 100 : 0;
  console.log('');
  console.log('--- Alerts ---');
  if (stuckPct > 15) {
    console.log(`WARN: awaiting_rider > 15% of today orders (${stuckPct.toFixed(1)}%)`);
  } else {
    console.log(`awaiting_rider share: ${stuckPct.toFixed(1)}% (threshold 15%)`);
  }
  if (onlineReady < 2) {
    console.log('WARN: fewer than 2 riders onlineReady — peak risk');
  }
  console.log(`Launch phase (launch_config/nonsung_90d): ${phase}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
