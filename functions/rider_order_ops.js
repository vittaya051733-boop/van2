const { HttpsError, onCall } = require('firebase-functions/v2/https');

let db;
let FieldValue;
let DEFAULT_REGION;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  DEFAULT_REGION = deps.DEFAULT_REGION;
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

const SETTLEMENT_DOC_PATH = 'platform_config/settlement';
const DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE = 0.15;

function readRiderPlatformDeductionRateFromSettlement(data) {
  if (!data || typeof data !== 'object') {
    return DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE;
  }
  const percent = readDouble(data.riderPlatformRatePercent);
  if (percent == null || percent < 0 || percent > 100) {
    return DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE;
  }
  return percent / 100;
}

async function loadRiderPlatformDeductionRate() {
  try {
    const snap = await db.doc(SETTLEMENT_DOC_PATH).get();
    return readRiderPlatformDeductionRateFromSettlement(snap.data());
  } catch (_) {
    return DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE;
  }
}

function computeRiderNetIncome(grossAmount, deductionRate) {
  const safeGross = roundMoney(grossAmount);
  if (safeGross <= 0) {
    return 0;
  }
  const rate =
    typeof deductionRate === 'number' && deductionRate >= 0 && deductionRate <= 1
      ? deductionRate
      : DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE;
  const platformFee = roundMoney(safeGross * rate);
  return roundMoney(safeGross - platformFee);
}

function isPayAtDestinationOrder(orderData) {
  if (!orderData || typeof orderData !== 'object') {
    return false;
  }
  const paymentStatus = String(orderData.paymentStatus || '').trim().toLowerCase();
  if (paymentStatus === 'cash_on_delivery') {
    return true;
  }
  if (
    orderData.payAtDestination === true ||
    orderData.paymentAtDestination === true ||
    orderData.isCod === true ||
    orderData.cashOnDelivery === true
  ) {
    return true;
  }

  const payment = orderData.payment && typeof orderData.payment === 'object'
    ? orderData.payment
    : null;
  const candidates = [
    orderData.paymentMethod,
    orderData.payMethod,
    orderData.paymentType,
    orderData.paymentChannel,
    payment?.method,
    payment?.paymentMethod,
    payment?.type,
    payment?.channel,
  ]
    .map((value) => String(value || '').trim().toLowerCase())
    .filter(Boolean);

  return candidates.some(
    (key) =>
      key.includes('cash_on_delivery') ||
      key.includes('cod') ||
      key.includes('pay_at_destination') ||
      key.includes('destination'),
  );
}

function resolveOrderShippingFee(orderData, fallbackGrossShippingFee) {
  if (fallbackGrossShippingFee != null && fallbackGrossShippingFee > 0) {
    return fallbackGrossShippingFee;
  }
  if (isTravelPassengerOrder(orderData)) {
    const travelFare = resolveTravelFareGross(orderData);
    if (travelFare > 0) {
      return travelFare;
    }
  }
  return (
    readDouble(orderData.shippingFee) ??
    readDouble(orderData.deliveryFee) ??
    readDouble(orderData.deliveryCharge) ??
    readDouble(orderData.shipping) ??
    0
  );
}

function isTravelPassengerOrder(orderData) {
  if (!orderData || typeof orderData !== 'object') {
    return false;
  }
  const orderType = String(orderData.orderType || '').trim();
  const serviceType = String(orderData.serviceType || '').trim();
  return orderType === 'travel_passenger' || serviceType === 'travel_passenger';
}

function resolveTravelFareGross(orderData) {
  const travelRequest = orderData.travelRequest;
  if (travelRequest && typeof travelRequest === 'object') {
    const fare = readDouble(travelRequest.fare);
    if (fare != null && fare > 0) {
      return fare;
    }
  }
  return (
    readDouble(orderData.grandTotal) ??
    readDouble(orderData.subtotal) ??
    readDouble(orderData.totalPrice) ??
    0
  );
}

function resolvePayAtDestinationHoldAmount(orderData) {
  const shippingFee = resolveOrderShippingFee(orderData);
  const productsSubtotal =
    readDouble(orderData.subtotal) ?? readDouble(orderData.totalPrice);
  const grandTotal = readDouble(orderData.grandTotal);
  if (grandTotal != null && grandTotal > 0) {
    return grandTotal;
  }

  const total = readDouble(orderData.total) ?? readDouble(orderData.totalAmount);
  if (total != null && total > 0) {
    if (productsSubtotal != null && productsSubtotal > 0 && shippingFee > 0) {
      const expected = productsSubtotal + shippingFee;
      if (Math.abs(total - expected) < 0.01) {
        return total;
      }
      if (Math.abs(total - productsSubtotal) < 0.01) {
        return total + shippingFee;
      }
    }
    return total;
  }

  if (productsSubtotal != null && productsSubtotal > 0) {
    return productsSubtotal + (shippingFee > 0 ? shippingFee : 0);
  }
  return 0;
}

function computeRiderNetShippingIncome(grossShippingFee, deductionRate) {
  return computeRiderNetIncome(grossShippingFee, deductionRate);
}

function estimateShopNetAmount(orderData) {
  if (isTravelPassengerOrder(orderData)) {
    return 0;
  }
  const merchantSubtotal = readDouble(orderData.merchantSubtotal);
  if (merchantSubtotal != null && merchantSubtotal > 0) {
    return merchantSubtotal;
  }
  const subtotal = readDouble(orderData.subtotal) ?? 0;
  if (subtotal > 0) {
    return subtotal;
  }
  const grandTotal = readDouble(orderData.grandTotal) ?? 0;
  const shipping =
    readDouble(orderData.shippingFee) ?? readDouble(orderData.deliveryFee) ?? 0;
  const fallback = grandTotal - shipping;
  return fallback > 0 ? fallback : grandTotal;
}

function buildDeliveryFinancialSnapshot({
  orderData,
  grossShippingFee,
  completedSource,
  deductionRate = DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE,
}) {
  const safeGross = roundMoney(resolveOrderShippingFee(orderData, grossShippingFee));
  const safeRate =
    typeof deductionRate === 'number' && deductionRate >= 0 && deductionRate <= 1
      ? deductionRate
      : DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE;
  const platformFee = roundMoney(safeGross * safeRate);
  const riderNetIncome = roundMoney(safeGross - platformFee);
  const now = FieldValue.serverTimestamp();
  const settlementType = isTravelPassengerOrder(orderData)
    ? 'travel_fare'
    : 'shipping_fee';

  if (isPayAtDestinationOrder(orderData)) {
    const collectedAmount = roundMoney(resolvePayAtDestinationHoldAmount(orderData));
    return {
      deliverySettlementType: 'pay_at_destination',
      deliveryGrossShippingFee: safeGross,
      deliveryPlatformFee: platformFee,
      deliveryRiderNetIncome: 0,
      deliveryCollectedAmount: collectedAmount,
      deliveryCreditReleaseAmount: 0,
      deliveryCompletedSource: completedSource,
      deliveryFinancials: {
        settlementType: 'pay_at_destination',
        grossShippingFee: safeGross,
        platformFee,
        riderNetIncome: 0,
        riderWalletTransfer: 0,
        collectedAmount,
        creditReleaseAmount: 0,
        deductionRate: safeRate,
        deductionRatePercent: roundMoney(safeRate * 100),
        currency: 'THB',
        completedAt: now,
        completedSource,
      },
    };
  }

  return {
    deliverySettlementType: settlementType,
    deliveryGrossShippingFee: safeGross,
    deliveryPlatformFee: platformFee,
    deliveryRiderNetIncome: riderNetIncome,
    deliveryCompletedSource: completedSource,
    deliveryFinancials: {
      settlementType,
      grossShippingFee: safeGross,
      platformFee,
      riderNetIncome,
      deductionRate: safeRate,
      deductionRatePercent: roundMoney(safeRate * 100),
      currency: 'THB',
      completedAt: now,
      completedSource,
    },
  };
}

function buildPendingSettlementPatch({ riderNetAmount, shopNetAmount }) {
  const now = FieldValue.serverTimestamp();
  const patch = {
    settlement: {},
  };
  if (riderNetAmount > 0) {
    patch.settlement.riderPayout = {
      status: 'pending',
      amount: roundMoney(riderNetAmount),
      updatedAt: now,
    };
  }
  if (shopNetAmount > 0) {
    patch.settlement.shopPayout = {
      status: 'pending',
      amount: roundMoney(shopNetAmount),
      updatedAt: now,
    };
  }
  return patch;
}

function readRecipientUid(value) {
  const text = String(value || '').trim();
  return text || null;
}

async function enqueuePayoutPendingNotifications({
  orderId,
  orderData,
  riderNetAmount,
  shopNetAmount,
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
      title: 'มียอดเงินเข้า',
      body: `ออเดอร์ ${orderLabel} ${roundMoney(shopNetAmount).toFixed(2)} บาท • รอชำระ`,
      action: 'payout_pending',
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
      title: 'มียอดเงินเข้า',
      body: `ออเดอร์ ${orderLabel} ${roundMoney(riderNetAmount).toFixed(2)} บาท • รอชำระ`,
      action: 'payout_pending',
      sourceApp: 'cloud_function',
      read: false,
      isRead: false,
      createdAt: now,
    });
  }

  await batch.commit();
}

function registerHandlers() {
  const rejectRiderOrder = onCall({ region: DEFAULT_REGION }, async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const uid = String(request.auth.uid).trim();
    const orderId = String(request.data?.orderId || '').trim();
    if (!orderId) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ orderId');
    }

    const orderRef = db.collection('orders').doc(orderId);
    const rejectableStatuses = new Set(['pending', 'awaiting_rider', 'accepted']);

    await db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError('not-found', 'ไม่พบออเดอร์');
      }

      const order = orderSnap.data() || {};
      const status = String(order.status || '').trim();
      if (status && !rejectableStatuses.has(status)) {
        throw new HttpsError(
          'failed-precondition',
          `ออเดอร์ไม่อยู่ในสถานะรอรับงาน (สถานะ: ${status || 'unknown'})`,
        );
      }

      const driverId = String(order.driverId || '').trim();
      if (driverId && driverId !== uid) {
        throw new HttpsError('permission-denied', 'ออเดอร์นี้ถูกจองโดยไรเดอร์คนอื่นแล้ว');
      }

      if (status === 'accepted') {
        const creditDocId = `order_pay_at_destination_${orderId}_${uid}`;
        const creditRef = db.collection('credits').doc(creditDocId);
        const creditSnap = await tx.get(creditRef);
        if (creditSnap.exists) {
          tx.delete(creditRef);
        }
      }

      tx.update(orderRef, {
        status: 'awaiting_rider',
        statusLabel: 'awaiting_nearest_rider',
        driverId: null,
        assignedRiderAt: null,
        acceptedAt: null,
        rejectedByDriverAt: FieldValue.serverTimestamp(),
        rejectedByDriverId: uid,
        riderNotifyReady: true,
        needsReassign: true,
        reassignReason: 'rider_rejected',
        reassignRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    return { success: true, orderId };
  });

  const completeRiderDelivery = onCall({ region: DEFAULT_REGION }, async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const uid = String(request.auth.uid).trim();
    const orderId = String(request.data?.orderId || '').trim();
    const completedSource = String(request.data?.completedSource || 'photo_proof').trim();
    const grossShippingFee = readDouble(request.data?.grossShippingFee);
    const deliveryProofImageUrl = String(request.data?.deliveryProofImageUrl || '').trim() || null;
    const deliveryProofStoragePath =
      String(request.data?.deliveryProofStoragePath || '').trim() || null;
    const deliveryProofCapturedByName =
      String(request.data?.deliveryProofCapturedByName || '').trim() || null;

    if (!orderId) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ orderId');
    }

    const orderRef = db.collection('orders').doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError('not-found', 'ไม่พบออเดอร์');
    }

    const order = orderSnap.data() || {};
    const driverId = String(order.driverId || '').trim();
    if (driverId !== uid) {
      throw new HttpsError('permission-denied', 'ออเดอร์นี้ไม่ได้รับโดยคุณ');
    }

    const status = String(order.status || '').trim();
    if (status !== 'delivering') {
      throw new HttpsError(
        'failed-precondition',
        `ออเดอร์ยังไม่ได้อยู่ระหว่างจัดส่ง (สถานะ: ${status || 'unknown'})`,
      );
    }

    const deductionRate = await loadRiderPlatformDeductionRate();
    const deliverySnapshot = buildDeliveryFinancialSnapshot({
      orderData: order,
      grossShippingFee,
      completedSource,
      deductionRate,
    });
    const riderNetAmount = deliverySnapshot.deliveryRiderNetIncome ?? 0;
    const shopNetAmount = estimateShopNetAmount(order);
    const settlementPatch = buildPendingSettlementPatch({
      riderNetAmount,
      shopNetAmount,
    });

    const updatePayload = {
      status: 'delivered',
      deliveredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...deliverySnapshot,
      ...settlementPatch,
    };

    if (deliveryProofImageUrl) {
      updatePayload.deliveryProofImageUrl = deliveryProofImageUrl;
      updatePayload.deliveryProofStoragePath = deliveryProofStoragePath;
      updatePayload.deliveryProofCapturedAt = FieldValue.serverTimestamp();
      updatePayload.deliveryProofCapturedById = uid;
      if (deliveryProofCapturedByName) {
        updatePayload.deliveryProofCapturedByName = deliveryProofCapturedByName;
      }
    }

    await orderRef.update(updatePayload);

    if (riderNetAmount > 0 || shopNetAmount > 0) {
      await enqueuePayoutPendingNotifications({
        orderId,
        orderData: { ...order, driverId: uid },
        riderNetAmount,
        shopNetAmount,
      });
    }

    return {
      success: true,
      orderId,
      riderNetAmount: roundMoney(riderNetAmount),
      shopNetAmount: roundMoney(shopNetAmount),
      deductionRatePercent: roundMoney(deductionRate * 100),
    };
  });

  const releaseRiderOrdersOnOffline = onCall({ region: DEFAULT_REGION }, async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const uid = String(request.auth.uid).trim();
    const isPassengerMode = request.data?.isPassengerMode === true;
    const activeStatuses = ['pending', 'accepted', 'ready', 'delivering'];

    const snapshot = await db
      .collection('orders')
      .where('driverId', '==', uid)
      .where('status', 'in', activeStatuses)
      .get();

    if (snapshot.empty) {
      return { success: true, releasedCount: 0 };
    }

    const batch = db.batch();
    let releasedCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const orderType = String(data.orderType || '').trim();
      const serviceType = String(data.serviceType || '').trim();
      const isTravel =
        orderType === 'travel_passenger' || serviceType === 'travel_passenger';
      if (isTravel !== isPassengerMode) {
        continue;
      }

      const status = String(data.status || '').trim();
      if (status === 'delivering') {
        continue;
      }

      batch.update(doc.ref, {
        driverId: null,
        previousDriverId: uid,
        needsReassign: true,
        reassignReason: 'rider_closed_ready',
        status: 'awaiting_rider',
        riderNotifyReady: false,
        reassignRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      releasedCount += 1;
    }

    if (releasedCount > 0) {
      await batch.commit();
    }

    return { success: true, releasedCount };
  });

  return {
    rejectRiderOrder,
    completeRiderDelivery,
    releaseRiderOrdersOnOffline,
  };
}

module.exports = {
  init,
  registerHandlers,
};
