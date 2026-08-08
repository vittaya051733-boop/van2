const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { assertVan4Admin } = require('./social/admin_guard');
const { createSettlementConfigLoader } = require('./settlement_config');

let db;
let FieldValue;
let Timestamp;
let onSchedule;
let logger;
let DEFAULT_REGION;
let loadSettlementConfig;
let computeReleaseTimestamp;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  Timestamp = deps.Timestamp;
  onSchedule = deps.onSchedule;
  logger = deps.logger;
  DEFAULT_REGION = deps.DEFAULT_REGION;

  const configLoader = createSettlementConfigLoader({ db });
  loadSettlementConfig = configLoader.loadSettlementConfig;
  computeReleaseTimestamp = (delayMinutes) =>
    configLoader.computeReleaseTimestamp(delayMinutes, Timestamp);
}

function readDouble(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function roundMoney(value) {
  return Math.round((readDouble(value) ?? 0) * 100) / 100;
}

function readRecipientUid(value) {
  const text = String(value || '').trim();
  return text || null;
}

function isTravelPassengerOrder(orderData) {
  const orderType = String(orderData?.orderType || '').trim();
  const serviceType = String(orderData?.serviceType || '').trim();
  return orderType === 'travel_passenger' || serviceType === 'travel_passenger';
}

function estimateShopProductSubtotal(orderData) {
  if (isTravelPassengerOrder(orderData)) {
    return 0;
  }
  const merchantSubtotal = readDouble(orderData?.merchantSubtotal);
  if (merchantSubtotal != null && merchantSubtotal > 0) {
    return merchantSubtotal;
  }
  const subtotal = readDouble(orderData?.subtotal) ?? 0;
  if (subtotal > 0) {
    return subtotal;
  }
  const grandTotal = readDouble(orderData?.grandTotal) ?? 0;
  const shipping =
    readDouble(orderData?.shippingFee) ?? readDouble(orderData?.deliveryFee) ?? 0;
  const fallback = grandTotal - shipping;
  return fallback > 0 ? fallback : grandTotal;
}

function estimateShopNetAmountWithGp(orderData, settlementConfig) {
  const productSubtotal = estimateShopProductSubtotal(orderData);
  if (productSubtotal <= 0) {
    return 0;
  }
  const gpRate = (settlementConfig?.gpRatePercent ?? 18) / 100;
  const leaderRate = (settlementConfig?.leaderRatePercent ?? 15) / 100;
  const afterGp = productSubtotal * (1 - gpRate);
  return roundMoney(afterGp * (1 - leaderRate));
}

function buildSettlementPatchOnComplete({
  orderData,
  isCod,
  riderNetAmount,
  shopNetAmount,
  settlementConfig,
}) {
  const now = FieldValue.serverTimestamp();
  const patch = {
    settlement: {},
  };
  const topLevel = {};

  const riderDelayMinutes = settlementConfig?.riderCreditDelayMinutes ?? 120;
  const shopDelayMinutes = settlementConfig?.shopCreditDelayMinutes ?? 120;
  const riderReleaseAt = computeReleaseTimestamp(riderDelayMinutes);
  const shopReleaseAt = computeReleaseTimestamp(shopDelayMinutes);

  if (riderNetAmount > 0) {
    if (isCod) {
      patch.settlement.riderCreditRelease = {
        status: 'scheduled',
        amount: roundMoney(riderNetAmount),
        scheduledReleaseAt: riderReleaseAt,
        delayMinutes: riderDelayMinutes,
        updatedAt: now,
      };
      topLevel.riderCreditReleaseStatus = 'scheduled';
      topLevel.riderCreditReleaseAt = riderReleaseAt;
    } else {
      patch.settlement.riderPayout = {
        status: 'scheduled',
        amount: roundMoney(riderNetAmount),
        scheduledReleaseAt: riderReleaseAt,
        delayMinutes: riderDelayMinutes,
        updatedAt: now,
      };
      topLevel.riderPayoutStatus = 'scheduled';
      topLevel.riderPayoutReleaseAt = riderReleaseAt;
    }
  }

  const existingShopPayout = orderData?.settlement?.shopPayout;
  const hasOmiseShopPayout =
    existingShopPayout &&
    String(existingShopPayout.paymentProvider || '').trim().toLowerCase() === 'omise';

  if (shopNetAmount > 0 && isCod) {
    patch.settlement.shopCreditRelease = {
      status: 'scheduled',
      amount: roundMoney(shopNetAmount),
      scheduledReleaseAt: shopReleaseAt,
      delayMinutes: shopDelayMinutes,
      updatedAt: now,
    };
    topLevel.shopCreditReleaseStatus = 'scheduled';
    topLevel.shopCreditReleaseAt = shopReleaseAt;
  } else if (shopNetAmount > 0 && !isCod && !hasOmiseShopPayout) {
    patch.settlement.shopPayout = {
      status: 'scheduled',
      amount: roundMoney(shopNetAmount),
      scheduledReleaseAt: shopReleaseAt,
      delayMinutes: shopDelayMinutes,
      updatedAt: now,
    };
    topLevel.shopPayoutStatus = 'scheduled';
    topLevel.shopPayoutReleaseAt = shopReleaseAt;
  }

  return { patch, topLevel };
}

async function enqueueCreditReleaseScheduledNotifications({
  orderId,
  orderData,
  riderNetAmount,
  shopNetAmount,
  riderDelayMinutes,
  shopDelayMinutes,
}) {
  const orderCode = String(orderData.orderCode || '').trim();
  const orderLabel = orderCode
    ? `#${orderCode}`
    : `#${orderId.substring(0, Math.min(orderId.length, 8))}`;
  const batch = db.batch();
  const now = FieldValue.serverTimestamp();

  const shopOwnerId = readRecipientUid(
    orderData.shopOwnerId || orderData.merchantId || orderData.shopId,
  );
  if (shopOwnerId && shopNetAmount > 0) {
    const ref = db.collection('app_notifications').doc();
    batch.set(ref, {
      targetApp: 'van1',
      recipientUid: shopOwnerId,
      orderId,
      title: 'รอปล่อยเครดิต',
      body: `ออเดอร์ ${orderLabel} ${roundMoney(shopNetAmount).toFixed(2)} บาท • รอ ~${shopDelayMinutes} นาที`,
      action: 'credit_release_scheduled',
      sourceApp: 'cloud_function',
      read: false,
      isRead: false,
      createdAt: now,
    });
  }

  const riderId = readRecipientUid(orderData.driverId || orderData.riderId);
  if (riderId && riderNetAmount > 0) {
    const ref = db.collection('app_notifications').doc();
    batch.set(ref, {
      targetApp: 'van3',
      recipientUid: riderId,
      orderId,
      title: 'รอปล่อยเครดิต',
      body: `ออเดอร์ ${orderLabel} ${roundMoney(riderNetAmount).toFixed(2)} บาท • รอ ~${riderDelayMinutes} นาที`,
      action: 'credit_release_scheduled',
      sourceApp: 'cloud_function',
      read: false,
      isRead: false,
      createdAt: now,
    });
  }

  await batch.commit();
}

async function enqueueCreditReleasedNotifications({
  orderId,
  orderData,
  targetApp,
  recipientUid,
  amount,
}) {
  if (!recipientUid || amount <= 0) {
    return;
  }
  const orderCode = String(orderData.orderCode || '').trim();
  const orderLabel = orderCode
    ? `#${orderCode}`
    : `#${orderId.substring(0, Math.min(orderId.length, 8))}`;
  await db.collection('app_notifications').add({
    targetApp,
    recipientUid,
    orderId,
    title: 'เครดิตเข้าแล้ว',
    body: `ออเดอร์ ${orderLabel} ${roundMoney(amount).toFixed(2)} บาท • เข้ากระเป๋าแล้ว`,
    action: 'credit_released',
    sourceApp: 'cloud_function',
    read: false,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function releaseTimestampMillis(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  return null;
}

async function releaseRiderCreditInTransaction(tx, { orderRef, orderId, orderData }) {
  const riderId = readRecipientUid(orderData.driverId || orderData.riderId);
  const release = orderData.settlement?.riderCreditRelease || {};
  const amount = roundMoney(release.amount);
  if (!riderId || amount <= 0) {
    return false;
  }

  const creditDocId = `order_rider_credit_release_${orderId}_${riderId}`;
  const creditRef = db.collection('credits').doc(creditDocId);
  const creditSnap = await tx.get(creditRef);
  if (creditSnap.exists) {
    return false;
  }

  tx.set(creditRef, {
    uid: riderId,
    amount,
    timestamp: FieldValue.serverTimestamp(),
    type: 'order_cod_rider_credit_release',
    orderId,
    source: 'scheduled_credit_release',
    creditedByCloudFunction: true,
  });

  tx.set(
    orderRef,
    {
      riderCreditReleaseStatus: 'released',
      settlement: {
        riderCreditRelease: {
          ...release,
          status: 'released',
          releasedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { riderId, amount };
}

async function releaseShopCreditInTransaction(tx, { orderRef, orderId, orderData }) {
  const shopOwnerId = readRecipientUid(
    orderData.shopOwnerId || orderData.merchantId || orderData.shopId,
  );
  const release = orderData.settlement?.shopCreditRelease || {};
  const amount = roundMoney(release.amount);
  if (!shopOwnerId || amount <= 0) {
    return false;
  }

  const creditDocId = `order_shop_credit_release_${orderId}_${shopOwnerId}`;
  const creditRef = db.collection('credits').doc(creditDocId);
  const creditSnap = await tx.get(creditRef);
  if (creditSnap.exists) {
    return false;
  }

  tx.set(creditRef, {
    uid: shopOwnerId,
    amount,
    timestamp: FieldValue.serverTimestamp(),
    type: 'order_cod_shop_credit_release',
    orderId,
    source: 'scheduled_credit_release',
    creditedByCloudFunction: true,
  });

  tx.set(
    orderRef,
    {
      shopCreditReleaseStatus: 'released',
      settlement: {
        shopCreditRelease: {
          ...release,
          status: 'released',
          releasedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { shopOwnerId, amount };
}

async function promoteShopPayoutInTransaction(tx, { orderRef, orderData }) {
  const payout = orderData.settlement?.shopPayout || {};
  const amount = roundMoney(payout.amount);
  if (amount <= 0) {
    return false;
  }

  tx.set(
    orderRef,
    {
      shopPayoutStatus: 'pending',
      settlement: {
        shopPayout: {
          ...payout,
          status: 'pending',
          promotedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { amount };
}

async function promoteRiderPayoutInTransaction(tx, { orderRef, orderData }) {
  const payout = orderData.settlement?.riderPayout || {};
  const amount = roundMoney(payout.amount);
  if (amount <= 0) {
    return false;
  }

  tx.set(
    orderRef,
    {
      riderPayoutStatus: 'pending',
      settlement: {
        riderPayout: {
          ...payout,
          status: 'pending',
          promotedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { amount };
}

async function processDueCreditReleases(nowDate = new Date()) {
  const nowMs = nowDate.getTime();
  let riderCreditsReleased = 0;
  let shopCreditsReleased = 0;
  let riderPayoutsPromoted = 0;
  let shopPayoutsPromoted = 0;

  const riderCreditSnap = await db
    .collection('orders')
    .where('riderCreditReleaseStatus', '==', 'scheduled')
    .where('riderCreditReleaseAt', '<=', Timestamp.fromDate(nowDate))
    .limit(100)
    .get();

  for (const doc of riderCreditSnap.docs) {
    const orderData = doc.data() || {};
    const releaseAtMs = releaseTimestampMillis(orderData.riderCreditReleaseAt);
    if (releaseAtMs != null && releaseAtMs > nowMs) {
      continue;
    }

    let releasedInfo = null;
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(doc.ref);
      if (!freshSnap.exists) {
        return;
      }
      const freshData = freshSnap.data() || {};
      if (freshData.riderCreditReleaseStatus !== 'scheduled') {
        return;
      }
      releasedInfo = await releaseRiderCreditInTransaction(tx, {
        orderRef: doc.ref,
        orderId: doc.id,
        orderData: freshData,
      });
    });

    if (releasedInfo && releasedInfo !== false) {
      riderCreditsReleased += 1;
      await enqueueCreditReleasedNotifications({
        orderId: doc.id,
        orderData,
        targetApp: 'van3',
        recipientUid: releasedInfo.riderId,
        amount: releasedInfo.amount,
      });
    }
  }

  const shopCreditSnap = await db
    .collection('orders')
    .where('shopCreditReleaseStatus', '==', 'scheduled')
    .where('shopCreditReleaseAt', '<=', Timestamp.fromDate(nowDate))
    .limit(100)
    .get();

  for (const doc of shopCreditSnap.docs) {
    const orderData = doc.data() || {};
    const releaseAtMs = releaseTimestampMillis(orderData.shopCreditReleaseAt);
    if (releaseAtMs != null && releaseAtMs > nowMs) {
      continue;
    }

    let releasedInfo = null;
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(doc.ref);
      if (!freshSnap.exists) {
        return;
      }
      const freshData = freshSnap.data() || {};
      if (freshData.shopCreditReleaseStatus !== 'scheduled') {
        return;
      }
      releasedInfo = await releaseShopCreditInTransaction(tx, {
        orderRef: doc.ref,
        orderId: doc.id,
        orderData: freshData,
      });
    });

    if (releasedInfo && releasedInfo !== false) {
      shopCreditsReleased += 1;
      await enqueueCreditReleasedNotifications({
        orderId: doc.id,
        orderData,
        targetApp: 'van1',
        recipientUid: releasedInfo.shopOwnerId,
        amount: releasedInfo.amount,
      });
    }
  }

  const riderPayoutSnap = await db
    .collection('orders')
    .where('riderPayoutStatus', '==', 'scheduled')
    .where('riderPayoutReleaseAt', '<=', Timestamp.fromDate(nowDate))
    .limit(100)
    .get();

  for (const doc of riderPayoutSnap.docs) {
    const orderData = doc.data() || {};
    const releaseAtMs = releaseTimestampMillis(orderData.riderPayoutReleaseAt);
    if (releaseAtMs != null && releaseAtMs > nowMs) {
      continue;
    }

    let promoted = false;
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(doc.ref);
      if (!freshSnap.exists) {
        return;
      }
      const freshData = freshSnap.data() || {};
      if (freshData.riderPayoutStatus !== 'scheduled') {
        return;
      }
      promoted = await promoteRiderPayoutInTransaction(tx, {
        orderRef: doc.ref,
        orderData: freshData,
      });
    });

    if (promoted) {
      riderPayoutsPromoted += 1;
    }
  }

  const shopPayoutSnap = await db
    .collection('orders')
    .where('shopPayoutStatus', '==', 'scheduled')
    .where('shopPayoutReleaseAt', '<=', Timestamp.fromDate(nowDate))
    .limit(100)
    .get();

  for (const doc of shopPayoutSnap.docs) {
    const orderData = doc.data() || {};
    const releaseAtMs = releaseTimestampMillis(orderData.shopPayoutReleaseAt);
    if (releaseAtMs != null && releaseAtMs > nowMs) {
      continue;
    }

    let promoted = false;
    await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(doc.ref);
      if (!freshSnap.exists) {
        return;
      }
      const freshData = freshSnap.data() || {};
      if (freshData.shopPayoutStatus !== 'scheduled') {
        return;
      }
      promoted = await promoteShopPayoutInTransaction(tx, {
        orderRef: doc.ref,
        orderData: freshData,
      });
    });

    if (promoted) {
      shopPayoutsPromoted += 1;
    }
  }

  return {
    riderCreditsReleased,
    shopCreditsReleased,
    riderPayoutsPromoted,
    shopPayoutsPromoted,
  };
}

function registerHandlers() {
  const processScheduledCreditReleases = onSchedule(
    {
      region: DEFAULT_REGION,
      schedule: 'every 5 minutes',
      timeZone: 'Asia/Bangkok',
    },
    async () => {
      const result = await processDueCreditReleases(new Date());
      logger.info('processScheduledCreditReleases done', result);
    },
  );

  const adminUpdateOrderCreditRelease = onCall({ region: DEFAULT_REGION }, async (request) => {
    await assertVan4Admin(request);

    const orderId = String(request.data?.orderId || '').trim();
    const target = String(request.data?.target || '').trim().toLowerCase();
    const action = String(request.data?.action || '').trim().toLowerCase();
    const reason = String(request.data?.reason || '').trim() || null;

    if (!orderId) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ orderId');
    }
    if (target !== 'rider' && target !== 'shop') {
      throw new HttpsError('invalid-argument', 'target ต้องเป็น rider หรือ shop');
    }

    const orderRef = db.collection('orders').doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'ไม่พบออเดอร์');
    }
    const orderData = orderSnap.data() || {};

    if (action === 'hold') {
      const statusField = target === 'rider' ? 'riderCreditReleaseStatus' : 'shopCreditReleaseStatus';
      const settlementKey = target === 'rider' ? 'riderCreditRelease' : 'shopCreditRelease';
      await orderRef.set(
        {
          [statusField]: 'held',
          settlement: {
            [settlementKey]: {
              ...(orderData.settlement?.[settlementKey] || {}),
              status: 'held',
              holdReason: reason,
              heldAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { success: true, orderId, target, action, status: 'held' };
    }

    if (action === 'unhold') {
      const settlementKey = target === 'rider' ? 'riderCreditRelease' : 'shopCreditRelease';
      const statusField = target === 'rider' ? 'riderCreditReleaseStatus' : 'shopCreditReleaseStatus';
      const atField = target === 'rider' ? 'riderCreditReleaseAt' : 'shopCreditReleaseAt';
      const existing = orderData.settlement?.[settlementKey] || {};
      const config = await loadSettlementConfig();
      const delayMinutes =
        target === 'rider'
          ? config.riderCreditDelayMinutes
          : config.shopCreditDelayMinutes;
      const releaseAt = computeReleaseTimestamp(delayMinutes);
      await orderRef.set(
        {
          [statusField]: 'scheduled',
          [atField]: releaseAt,
          settlement: {
            [settlementKey]: {
              ...existing,
              status: 'scheduled',
              scheduledReleaseAt: releaseAt,
              holdReason: null,
              updatedAt: FieldValue.serverTimestamp(),
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { success: true, orderId, target, action, status: 'scheduled' };
    }

    if (action === 'block') {
      const statusField = target === 'rider' ? 'riderCreditReleaseStatus' : 'shopCreditReleaseStatus';
      const settlementKey = target === 'rider' ? 'riderCreditRelease' : 'shopCreditRelease';
      await orderRef.set(
        {
          [statusField]: 'blocked',
          settlement: {
            [settlementKey]: {
              ...(orderData.settlement?.[settlementKey] || {}),
              status: 'blocked',
              holdReason: reason,
              blockedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { success: true, orderId, target, action, status: 'blocked' };
    }

    if (action === 'release_now') {
      if (target === 'rider') {
        let releasedInfo = null;
        await db.runTransaction(async (tx) => {
          const freshSnap = await tx.get(orderRef);
          const freshData = freshSnap.data() || {};
          releasedInfo = await releaseRiderCreditInTransaction(tx, {
            orderRef,
            orderId,
            orderData: freshData,
          });
        });
        if (!releasedInfo) {
          throw new HttpsError('failed-precondition', 'ไม่สามารถปล่อยเครดิตไรเดอร์ได้');
        }
        await enqueueCreditReleasedNotifications({
          orderId,
          orderData,
          targetApp: 'van3',
          recipientUid: releasedInfo.riderId,
          amount: releasedInfo.amount,
        });
        return { success: true, orderId, target, action, status: 'released' };
      }

      let releasedInfo = null;
      await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(orderRef);
        const freshData = freshSnap.data() || {};
        releasedInfo = await releaseShopCreditInTransaction(tx, {
          orderRef,
          orderId,
          orderData: freshData,
        });
      });
      if (!releasedInfo) {
        throw new HttpsError('failed-precondition', 'ไม่สามารถปล่อยเครดิตร้านค้าได้');
      }
      await enqueueCreditReleasedNotifications({
        orderId,
        orderData,
        targetApp: 'van1',
        recipientUid: releasedInfo.shopOwnerId,
        amount: releasedInfo.amount,
      });
      return { success: true, orderId, target, action, status: 'released' };
    }

    throw new HttpsError(
      'invalid-argument',
      'action ต้องเป็น hold, unhold, block หรือ release_now',
    );
  });

  return {
    processScheduledCreditReleases,
    adminUpdateOrderCreditRelease,
  };
}

module.exports = {
  init,
  registerHandlers,
  buildSettlementPatchOnComplete,
  enqueueCreditReleaseScheduledNotifications,
  estimateShopNetAmountWithGp,
  processDueCreditReleases,
};
