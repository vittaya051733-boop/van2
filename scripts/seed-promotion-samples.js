/**
 * Seed sample promotions/coupons for van2 testing.
 * Run: node scripts/seed-promotion-samples.js
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'van-merchant' });
}

const db = admin.firestore();
const now = admin.firestore.Timestamp.now();
const in30Days = admin.firestore.Timestamp.fromMillis(
  Date.now() + 30 * 24 * 60 * 60 * 1000,
);

async function main() {
  const batch = db.batch();

  const displayConfigRef = db.collection('promotion_display_config').doc('global');
  batch.set(
    displayConfigRef,
    {
      cartStyle: 'expanded',
      showAutoPromotionsInCart: true,
      showCouponField: true,
      homePromoBanner: true,
      productBadge: true,
      note: 'Sample config for van2 promo/coupon UI testing',
      updatedAt: now,
    },
    { merge: true },
  );

  const promoRef = db.collection('promotions').doc('sample_market_promo');
  batch.set(
    promoRef,
    {
      name: 'ลด 10% ตลาดเว้น (ทดสอบ)',
      active: true,
      priority: 100,
      stackableWithCoupon: true,
      redemptionCount: 0,
      discount: {
        type: 'percent',
        value: 10,
        maxDiscount: 100,
        applyTo: 'subtotal',
      },
      display: {
        shortLabel: 'ลด 10% ตลาดเว้น',
        homeBannerText: 'ลด 10% เมื่อซื้อในตลาดเว้น — ขั้นต่ำ ฿200',
        badgeText: 'ลด 10%',
      },
      conditions: {
        minSubtotal: 200,
        minItemCount: 1,
        maxRedemptionsTotal: 10000,
        maxRedemptionsPerUser: 5,
        productIds: [],
        shopIds: [],
        geo: { type: 'market_hub' },
        startAt: now,
        endAt: in30Days,
      },
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  const couponRef = db.collection('coupons').doc('sample_vantalad50');
  batch.set(
    couponRef,
    {
      code: 'VANTALAD50',
      name: 'คูปองทดสอบ VANTALAD50',
      active: true,
      stackableWithPromotion: true,
      redemptionCount: 0,
      discount: {
        type: 'fixed',
        value: 50,
        applyTo: 'subtotal',
      },
      display: {
        shortLabel: 'ลด ฿50',
        homeBannerText: 'ใช้โค้ด VANTALAD50 ลด 50 บาท',
        badgeText: '',
      },
      conditions: {
        minSubtotal: 300,
        minItemCount: 1,
        maxRedemptionsTotal: 5000,
        maxRedemptionsPerUser: 3,
        productIds: [],
        shopIds: [],
        geo: { type: 'none' },
        startAt: now,
        endAt: in30Days,
      },
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  await batch.commit();
  console.log('Seeded: promotion_display_config/global');
  console.log('Seeded: promotions/sample_market_promo');
  console.log('Seeded: coupons/sample_vantalad50 (code VANTALAD50)');
}

main().catch((error) => {
  console.error('Seed failed:', error);
  process.exit(1);
});
