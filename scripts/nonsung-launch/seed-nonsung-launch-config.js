/**
 * Seed Non Sung 90-day soft launch config (promotions, coupons, pricing, settlement).
 *
 * Requires ADC: gcloud auth application-default login
 * Dry run: node seed-nonsung-launch-config.js --dry-run
 * Apply:    node seed-nonsung-launch-config.js --confirm APPROVE:nonsung:van-merchant
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', '..', 'functions', 'node_modules', 'firebase-admin'));

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'van-merchant';
const CONFIRM_TOKEN = 'APPROVE:nonsung:van-merchant';

// ตลาดโนนสูง — ปรับพิกัดหลังสำรวจจริง
const NONSUNG_HUB = {
  latitude: 17.271,
  longitude: 102.638,
  radiusMeters: 8000,
};

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const confirmArg = args.find((a) => a.startsWith('--confirm='))?.split('=')[1]
  || (args.includes('--confirm') ? args[args.indexOf('--confirm') + 1] : null);
const paymentNameArg = args.find((a) => a.startsWith('--payment-name='))?.split('=')[1]
  || (args.includes('--payment-name') ? args[args.indexOf('--payment-name') + 1] : null);
const paymentBankArg = args.find((a) => a.startsWith('--payment-bank='))?.split('=')[1]
  || (args.includes('--payment-bank') ? args[args.indexOf('--payment-bank') + 1] : null);
const paymentAccountArg = args.find((a) => a.startsWith('--payment-account='))?.split('=')[1]
  || (args.includes('--payment-account') ? args[args.indexOf('--payment-account') + 1] : null);
const promptPayPhoneArg = args.find((a) => a.startsWith('--promptpay-phone='))?.split('=')[1]
  || (args.includes('--promptpay-phone') ? args[args.indexOf('--promptpay-phone') + 1] : null);
const promptPayIdArg = args.find((a) => a.startsWith('--promptpay-id='))?.split('=')[1]
  || (args.includes('--promptpay-id') ? args[args.indexOf('--promptpay-id') + 1] : null);

function cleanOrNull(value) {
  if (value == null) {
    return null;
  }
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();
const now = admin.firestore.Timestamp.now();
const in90Days = admin.firestore.Timestamp.fromMillis(Date.now() + 90 * 24 * 60 * 60 * 1000);
const in45Days = admin.firestore.Timestamp.fromMillis(Date.now() + 45 * 24 * 60 * 60 * 1000);
const paymentConfig = {
  recipientDisplayName: cleanOrNull(paymentNameArg) || 'วิทยา ทนหงษา',
  bankName: cleanOrNull(paymentBankArg) || 'ธนาคารกสิกรไทย',
  bankAccountNumber: cleanOrNull(paymentAccountArg) || '1643440349',
  promptPayPhoneNumber: cleanOrNull(promptPayPhoneArg),
  promptPayNationalIdOrTaxId: cleanOrNull(promptPayIdArg) || '1410400168710',
  slipProviderLabel: 'Slip OK',
  note: 'Non Sung payment config locked from seed script',
  launchLabel: 'nonsung_90d',
  locked: true,
  lockedAt: now,
  updatedAt: now,
};

const geoNonsung = {
  type: 'market_hub',
  latitude: NONSUNG_HUB.latitude,
  longitude: NONSUNG_HUB.longitude,
  radiusMeters: NONSUNG_HUB.radiusMeters,
};

function buildPayload() {
  return {
    'promotion_display_config/global': {
      cartStyle: 'expanded',
      showAutoPromotionsInCart: true,
      showCouponField: true,
      homePromoBanner: true,
      productBadge: true,
      note: 'Non Sung 90-day soft launch — van4 can override',
      updatedAt: now,
    },
    'promotions/nonsung_launch_banner': {
      name: 'เปิดตัวตลาดโนนสูง — ลดค่าส่ง',
      active: true,
      priority: 200,
      stackableWithCoupon: true,
      redemptionCount: 0,
      discount: {
        type: 'percent',
        value: 15,
        maxDiscount: 40,
        applyTo: 'shipping',
      },
      display: {
        shortLabel: 'ลดค่าส่ง 15%',
        homeBannerText: 'เปิดตัวโนนสูง — ลดค่าส่งสูงสุด ฿40 (ซื้อขั้นต่ำ ฿150)',
        badgeText: 'โนนสูง',
      },
      conditions: {
        minSubtotal: 150,
        minItemCount: 1,
        maxRedemptionsTotal: 5000,
        maxRedemptionsPerUser: 10,
        productIds: [],
        shopIds: [],
        geo: geoNonsung,
        startAt: now,
        endAt: in90Days,
      },
      createdAt: now,
      updatedAt: now,
    },
    'coupons/nonsung50': {
      code: 'NONSUNG50',
      name: 'คูปองเปิดตัวโนนสูง NONSUNG50',
      active: true,
      stackableWithPromotion: true,
      redemptionCount: 0,
      discount: {
        type: 'fixed',
        value: 50,
        applyTo: 'shipping',
      },
      display: {
        shortLabel: 'ลดค่าส่ง ฿50',
        homeBannerText: 'โค้ด NONSUNG50 ลดค่าส่ง 50 บาท (จำกัด 100 สิทธิ์)',
        badgeText: 'NONSUNG50',
      },
      conditions: {
        minSubtotal: 200,
        minItemCount: 1,
        maxRedemptionsTotal: 100,
        maxRedemptionsPerUser: 1,
        productIds: [],
        shopIds: [],
        geo: geoNonsung,
        startAt: now,
        endAt: in45Days,
      },
      createdAt: now,
      updatedAt: now,
    },
    'pricing_config/global': {
      note: 'Non Sung pilot — ค่าส่งระยะสั้นรอบตลาด (merge กับค่าเดิมใน van4)',
      shippingBaseFee: 25,
      shippingPerKmFee: 8,
      shippingMinBillableKm: 1,
      shippingMissingCoordsFee: 35,
      updatedAt: now,
    },
    'platform_config/settlement': {
      gpRatePercent: 8,
      riderPlatformRatePercent: 5,
      leaderRatePercent: 2,
      note: 'Non Sung soft launch defaults — ปรับใน van4 Admin',
      updatedAt: now,
    },
    'payment_config/collection': paymentConfig,
    'launch_config/nonsung_90d': {
      phase: 'prep',
      marketName: 'ตลาดโนนสูง',
      amphoe: 'โนนสูง',
      province: 'อุดรธานี',
      hub: NONSUNG_HUB,
      peakHours: ['07:00-10:00', '16:00-20:00'],
      targets: {
        shopsActive: 30,
        ridersPeak: 5,
        ordersPerDay: 20,
        repeatRate30d: 0.3,
      },
      kpiWeeks: [
        { week: 3, shops: 15, ordersPerDay: '3-5', ridersPeak: 2 },
        { week: 4, shops: 20, ordersPerDay: '5-8', ridersPeak: 2 },
        { week: 5, shops: 25, ordersPerDay: '8-12', ridersPeak: 3 },
        { week: 6, shops: 28, ordersPerDay: '10-15', ridersPeak: 3 },
      ],
      lineGroups: {
        shops: 'ร้านโนนสูง',
        riders: 'ไรเดอร์โนนสูง',
        admin: 'แอดมิน',
      },
      paymentConfigLocked: true,
      paymentConfigLockedAt: now,
      createdAt: now,
      updatedAt: now,
    },
  };
}

async function main() {
  const payload = buildPayload();
  const paths = Object.keys(payload);

  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Documents to merge: ${paths.length}`);
  for (const docPath of paths) {
    console.log(`  - ${docPath}`);
  }

  if (dryRun) {
    console.log('\nDry run only — no writes.');
    return;
  }

  if (confirmArg !== CONFIRM_TOKEN) {
    console.error(`\nRefusing write. Pass --confirm ${CONFIRM_TOKEN}`);
    process.exit(1);
  }

  if (
    paymentConfig.recipientDisplayName.startsWith('REPLACE_ME') ||
    paymentConfig.bankName.startsWith('REPLACE_ME') ||
    paymentConfig.bankAccountNumber.startsWith('REPLACE_ME')
  ) {
    console.error('\nRefusing write because payment_config still has placeholder values.');
    process.exit(1);
  }

  const batch = db.batch();
  for (const [docPath, data] of Object.entries(payload)) {
    const slash = docPath.indexOf('/');
    const collection = docPath.slice(0, slash);
    const id = docPath.slice(slash + 1);
    batch.set(db.collection(collection).doc(id), data, { merge: true });
  }

  await batch.commit();
  console.log('\nSeeded Non Sung launch config.');
  console.log('payment_config/collection locked for Non Sung launch.');
  console.log('Coupon code for customers: NONSUNG50');
}

main().catch((error) => {
  console.error('Seed failed:', error);
  process.exit(1);
});
