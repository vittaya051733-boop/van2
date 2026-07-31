/**
 * Travel fare smoke test (production-safe):
 * Run: node scripts/smoke-test/verify-travel-fare.js  (from van2/functions)
 */
const { readFileSync, existsSync } = require('fs');
const { join } = require('path');

const functionsDir = join(__dirname, '..', '..', 'functions');
const admin = require(join(functionsDir, 'node_modules/firebase-admin'));
const {
  createTravelOrderHandler,
  computeTravelFareForVehicle,
} = require(join(functionsDir, 'travel_orders'));

const PROJECT_ID = 'van-merchant';
const CONFIG_PATH = join(__dirname, '..', 'smoke-test-config.local.json');

function parseNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function van2ClientFare(distanceKm, vehicleType, rates) {
  const normalizedKm = Number.isFinite(distanceKm) && distanceKm >= 0 ? distanceKm : 0;
  const minKm = rates.travelMinBillableKm ?? 1;
  const billableKm = normalizedKm < minKm ? minKm : normalizedKm;
  const base =
    (rates.travelBaseFee ?? 25) + (billableKm - minKm) * (rates.travelPerKmFee ?? 12.5);
  const multipliers = { motorcycle: 1, sedan: 1.25, pickup: 1.45 };
  const multiplier = multipliers[vehicleType] ?? 1;
  return Math.round(base * multiplier * 100) / 100;
}

async function loadPricingRates(db) {
  const snap = await db.doc('pricing_config/global').get();
  const data = snap.data() || {};
  return {
    travelBaseFee: parseNumber(data.travelBaseFee ?? 25),
    travelPerKmFee: parseNumber(data.travelPerKmFee ?? 12.5),
    travelMinBillableKm: parseNumber(data.travelMinBillableKm ?? 1),
  };
}

function assertClose(label, actual, expected, tolerance = 0.01) {
  if (Math.abs(actual - expected) > tolerance) {
    throw new Error(`${label}: expected ${expected}, got ${actual}`);
  }
  console.log(`PASS ${label}: ${actual}`);
}

function omiseAmountGuard(sessionAmount, fare) {
  if (Math.abs(sessionAmount - fare) > 0.01) {
    throw new Error('ยอดชำระ Omise ไม่ตรงกับค่าเดินทาง');
  }
}

async function ensureSmokeCustomerUid(auth) {
  if (existsSync(CONFIG_PATH)) {
    const config = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
    const configured = String(config.customerUid || '').trim();
    if (configured) {
      return configured;
    }
  }

  const uid = `smoke-travel-${Date.now()}`;
  await auth.createUser({
    uid,
    email: `${uid}@smoke.van.local`,
    emailVerified: true,
  });
  return uid;
}

async function run() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const rates = await loadPricingRates(db);

  console.log('=== 1) Formula parity (van2 UI vs createTravelOrder CF) ===');
  console.log('pricing', JSON.stringify(rates));
  const samples = [
    [0.51, 'motorcycle'],
    [5.2, 'motorcycle'],
    [5.2, 'sedan'],
    [12.3, 'pickup'],
    [40.397, 'motorcycle'],
  ];
  for (const [km, vehicleType] of samples) {
    const server = computeTravelFareForVehicle(km, vehicleType, rates, parseNumber);
    const client = van2ClientFare(km, vehicleType, rates);
    assertClose(`formula ${km}km ${vehicleType}`, server, client);
  }

  console.log('\n=== 2) Omise amount guard ===');
  const fareSample = computeTravelFareForVehicle(5.2, 'motorcycle', rates, parseNumber);
  omiseAmountGuard(fareSample, fareSample);
  console.log(`PASS omise guard accepts matching amount ${fareSample}`);
  let omiseMismatchThrown = false;
  try {
    omiseAmountGuard(fareSample - 8, fareSample);
  } catch (error) {
    omiseMismatchThrown = String(error.message || error).includes(
      'ยอดชำระ Omise ไม่ตรงกับค่าเดินทาง',
    );
  }
  if (!omiseMismatchThrown) {
    throw new Error('Omise guard should reject mismatched amount');
  }
  console.log('PASS omise guard rejects stale/wrong amount (+8 old-formula drift)');

  console.log('\n=== 3) Live COD createTravelOrder -> Firestore totals ===');
  const uid = await ensureSmokeCustomerUid(admin.auth());
  const distanceKm = 5.2;
  const vehicleType = 'motorcycle';
  const expectedFare = computeTravelFareForVehicle(
    distanceKm,
    vehicleType,
    rates,
    parseNumber,
  );
  const idempotencyKey = `smoke-fare-${Date.now()}`;

  const deps = {
    db,
    admin,
    FieldValue,
    HttpsError: class SmokeHttpsError extends Error {
      constructor(code, message) {
        super(message);
        this.code = code;
      }
    },
    parseNumber,
    getPricingRates: async () => rates,
  };

  const result = await createTravelOrderHandler(
    {
      auth: {
        uid,
        token: { firebase: { sign_in_provider: 'password' } },
      },
      data: {
        pickup: {
          latitude: 17.279792,
          longitude: 102.870767,
          title: 'Smoke Pickup',
          subtitle: 'Non Sung hub',
        },
        destination: {
          latitude: 17.295,
          longitude: 102.885,
          title: 'Smoke Destination',
          subtitle: 'Near hub',
        },
        distanceKm,
        vehicleType,
        vehicleTypeLabel: 'มอเตอร์ไซค์',
        paymentMethod: 'cash_on_delivery',
        paymentMethodLabel: 'จ่ายปลายทาง',
        paymentStatus: 'cash_on_delivery',
        paymentStatusLabel: 'ชำระปลายทาง',
        scheduleLabel: 'ให้รถออกตอนนี้',
        isImmediate: true,
        notifyRider: false,
        riderNotifyReady: false,
        idempotencyKey,
      },
    },
    deps,
  );

  assertClose('CF combinedGrandTotal', parseNumber(result.combinedGrandTotal), expectedFare);

  const orderId = Array.isArray(result.orderIds) ? result.orderIds[0] : null;
  if (!orderId) {
    throw new Error('createTravelOrder returned no orderIds');
  }

  const orderSnap = await db.collection('orders').doc(orderId).get();
  const order = orderSnap.data() || {};
  const travelRequest = order.travelRequest || {};

  assertClose('Firestore grandTotal', parseNumber(order.grandTotal), expectedFare);
  assertClose('Firestore travelRequest.fare', parseNumber(travelRequest.fare), expectedFare);
  assertClose('Firestore totalPrice (rider/customer)', parseNumber(order.totalPrice), expectedFare);
  assertClose('Firestore subtotal', parseNumber(order.subtotal), expectedFare);

  console.log('\n=== Summary ===');
  console.log(
    JSON.stringify(
      {
        orderId,
        orderCode: order.orderCode,
        paymentStatus: order.paymentStatus,
        distanceKm,
        vehicleType,
        expectedFare,
        grandTotal: order.grandTotal,
        riderViewTotal: order.totalPrice,
        customerMatchesFirestore: true,
        riderMatchesCustomer: true,
      },
      null,
      2,
    ),
  );
  console.log('\nALL TRAVEL FARE SMOKE TESTS PASSED');
}

run().catch((error) => {
  console.error('FAIL travel fare smoke:', error?.message || error);
  process.exit(1);
});
