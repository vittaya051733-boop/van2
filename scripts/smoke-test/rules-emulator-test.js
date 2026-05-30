/**
 * Rules smoke test (emulator) — validates rider order/riders reads after rule changes.
 */
const { readFileSync, existsSync } = require('fs');
const { join } = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = join(__dirname, '..', '..', 'firestore.rules');

async function seed(testEnv, riderUid) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const adminDb = ctx.firestore();
    await adminDb.collection('orders').doc('smoke-order-promptpay').set({
      driverId: riderUid,
      customerId: 'smoke-customer-uid',
      shopOwnerId: 'smoke-shop-uid',
      status: 'pending',
      sourceApp: 'van2_customer',
      paymentMethod: 'promptpay_qr',
      paymentStatus: 'pending',
      customerConfirmed: true,
      riderNotifyReady: true,
      customerConfirmedAt: new Date(),
      audit: { createdSource: 'cod_confirm_dialog' },
    });
    await adminDb.collection('orders').doc('smoke-order-accepted').set({
      driverId: riderUid,
      customerId: 'smoke-customer-uid',
      shopOwnerId: 'smoke-shop-uid',
      status: 'accepted',
      sourceApp: 'van2_customer',
      paymentMethod: 'cod',
      customerConfirmed: true,
      riderNotifyReady: true,
      customerConfirmedAt: new Date(),
      audit: { createdSource: 'cod_confirm_dialog' },
    });
    await adminDb.collection('riders').doc(riderUid).set({
      onlineReady: true,
      fcmToken: 'smoke-token',
    });
    await adminDb.collection('customer_users').doc('smoke-customer-uid').set({
      displayName: 'Smoke Customer',
    });
  });
}

async function run() {
  if (!existsSync(RULES_PATH)) {
    throw new Error(`Missing rules file: ${RULES_PATH}`);
  }

  const rules = readFileSync(RULES_PATH, 'utf8');
  const riderUid = 'smoke-rider-uid';
  const testEnv = await initializeTestEnvironment({
    projectId: 'van-smoke-rules-test',
    firestore: { rules },
  });

  try {
    await seed(testEnv, riderUid);
    const riderDb = testEnv.authenticatedContext(riderUid).firestore();

    await assertSucceeds(
      riderDb.collection('orders').where('driverId', '==', riderUid).get(),
      'rider orders query (driverId == uid)',
    );
    await assertSucceeds(
      riderDb.collection('riders').doc(riderUid).get(),
      'rider profile read',
    );
    await assertSucceeds(
      riderDb.collection('orders').doc('smoke-order-promptpay').get(),
      'assigned promptpay order single read',
    );

    const customerDb = testEnv.authenticatedContext('smoke-customer-uid').firestore();
    await assertSucceeds(
      customerDb.collection('customer_users').doc('smoke-customer-uid').get(),
      'customer profile read',
    );

    console.log('PASS rules-emulator: van3 orders/riders + van2 customer paths');
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((error) => {
  console.error('FAIL rules-emulator:', error.message || error);
  process.exit(1);
});
