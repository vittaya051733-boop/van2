const { findNearestTravelRider } = require('./travel_orders');

const TERMINAL_STATUSES = new Set([
  'cancelled',
  'refund',
  'refunded',
  'completed',
  'delivered',
]);

const MAX_ORDERS_PER_RUN = 40;

let db;
let FieldValue;
let logger;
let findNearestRiderForShop;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  logger = deps.logger;
  findNearestRiderForShop = deps.findNearestRiderForShop;
}

function readString(value) {
  return String(value ?? '').trim();
}

function isTravelOrder(data) {
  const orderType = readString(data.orderType);
  const serviceType = readString(data.serviceType);
  return orderType === 'travel_passenger' || serviceType === 'travel_passenger';
}

function isCashOnDelivery(data) {
  const paymentStatus = readString(data.paymentStatus).toLowerCase();
  const paymentMethod = readString(data.paymentMethod).toLowerCase();
  return paymentStatus === 'cash_on_delivery' || paymentMethod === 'cash_on_delivery';
}

function isRiderNotifyReady(data) {
  if (data.riderNotifyReady === true) {
    return true;
  }
  const paymentStatus = readString(data.paymentStatus).toLowerCase();
  return paymentStatus === 'verified' || isCashOnDelivery(data);
}

function isOrderEligibleForRiderMatch(data) {
  const status = readString(data.status);
  if (status !== 'awaiting_rider') {
    return false;
  }
  if (readString(data.driverId)) {
    return false;
  }
  if (!isRiderNotifyReady(data)) {
    return false;
  }
  if (data.customerConfirmed !== true) {
    return false;
  }
  if (TERMINAL_STATUSES.has(status.toLowerCase())) {
    return false;
  }

  const paymentStatus = readString(data.paymentStatus).toLowerCase();
  if (paymentStatus === 'awaiting_slip_review') {
    return false;
  }

  const fulfillmentType = readString(data.fulfillmentType);
  if (fulfillmentType === 'external_courier') {
    return false;
  }

  return true;
}

function readPickupCoordinates(data) {
  if (isTravelOrder(data)) {
    const travelRequest = data.travelRequest;
    if (travelRequest && typeof travelRequest === 'object') {
      const pickup = travelRequest.pickup;
      if (pickup && typeof pickup === 'object') {
        const lat = Number(pickup.latitude);
        const lng = Number(pickup.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          return { lat, lng };
        }
      }
    }
  }

  const shopSnapshot =
    data.shopSnapshot && typeof data.shopSnapshot === 'object'
      ? data.shopSnapshot
      : null;
  const lat = Number(data.shopLatitude ?? shopSnapshot?.shopLatitude);
  const lng = Number(data.shopLongitude ?? shopSnapshot?.shopLongitude);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    return { lat, lng };
  }

  const shopLocation = data.shopLocation;
  if (shopLocation && typeof shopLocation === 'object') {
    const geoLat = Number(shopLocation.latitude);
    const geoLng = Number(shopLocation.longitude);
    if (Number.isFinite(geoLat) && Number.isFinite(geoLng)) {
      return { lat: geoLat, lng: geoLng };
    }
  }

  return null;
}

function readTravelVehicleType(data) {
  const travelRequest = data.travelRequest;
  if (travelRequest && typeof travelRequest === 'object') {
    const fromRequest = readString(travelRequest.vehicleType);
    if (fromRequest) {
      return fromRequest;
    }
  }
  return readString(data.vehicleType) || 'motorcycle';
}

function buildRiderSearchPatch(riderSearch, assignedRider) {
  return {
    stepKm: 2,
    maxRadiusKm: 10,
    searchedRadiusKm: riderSearch.searchedRadiusKm ?? null,
    onlineRiderCount: riderSearch.onlineRiderCount ?? 0,
    eligibleRiderCount: riderSearch.eligibleRiderCount ?? 0,
    matched: true,
    matchedRiderId: assignedRider.riderId,
    matchedDistanceKm: assignedRider.distanceKm ?? null,
    autoMatchedAt: FieldValue.serverTimestamp(),
    autoMatchReason: riderSearch.reason || 'pending_order_rider_match',
    ...(riderSearch.excludedRiderCount > 0
      ? { excludedRiderCount: riderSearch.excludedRiderCount }
      : {}),
    ...(Object.keys(riderSearch.excludedBreakdown || {}).length > 0
      ? { excludedBreakdown: riderSearch.excludedBreakdown }
      : {}),
  };
}

async function findRiderForOrder(data) {
  const coords = readPickupCoordinates(data);
  if (!coords) {
    return {
      rider: null,
      reason: 'missing_pickup_coordinates',
      onlineRiderCount: 0,
      eligibleRiderCount: 0,
      searchedRadiusKm: 0,
      excludedRiderCount: 0,
      excludedBreakdown: {},
    };
  }

  if (isTravelOrder(data)) {
    return findNearestTravelRider(
      db,
      coords.lat,
      coords.lng,
      readTravelVehicleType(data),
    );
  }

  return findNearestRiderForShop(db, coords.lat, coords.lng);
}

function buildRiderNotificationPayload({ orderId, orderData, riderId }) {
  const orderCode = readString(orderData.orderCode);
  const shopName = readString(orderData.shopName) || 'ร้านค้า';
  const paymentStatus = readString(orderData.paymentStatus).toLowerCase();
  const isVerifiedPayment = paymentStatus === 'verified';
  const travel = isTravelOrder(orderData);

  if (travel) {
    const pickupTitle =
      readString(orderData.travelRequest?.pickup?.title) || shopName;
    return {
      targetApp: 'van3',
      recipientUid: riderId,
      orderId,
      title: isVerifiedPayment ? 'ชำระเงินแล้ว มีงานเดินทางใหม่' : 'มีคำขอเดินทางใหม่',
      body: orderCode
        ? isVerifiedPayment
          ? `งานเดินทาง ${orderCode} ชำระเงินแล้ว`
          : `งานเดินทาง ${orderCode} จาก ${pickupTitle}`
        : `มีงานเดินทางใหม่จาก ${pickupTitle}`,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
      source: 'van2_customer',
      sourceApp: 'van2_customer',
      action: isVerifiedPayment
        ? 'order_payment_verified'
        : 'travel_order_created_customer_confirmed',
      customerConfirmed: true,
      riderNotifyReady: true,
    };
  }

  return {
    targetApp: 'van3',
    recipientUid: riderId,
    orderId,
    title: isVerifiedPayment ? 'ชำระเงินแล้ว มีออเดอร์ใหม่' : 'มีคำสั่งซื้อใหม่',
    body: orderCode
      ? isVerifiedPayment
        ? `ออเดอร์ ${orderCode} ชำระเงินแล้ว`
        : `ออเดอร์ ${orderCode} จาก ${shopName}`
      : isVerifiedPayment
        ? 'มีออเดอร์ที่ชำระเงินแล้ว'
        : `มีคำสั่งซื้อใหม่จาก ${shopName}`,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
    source: 'van2_customer',
    sourceApp: 'van2_customer',
    action: isVerifiedPayment
      ? 'order_payment_verified'
      : 'order_created_customer_confirmed',
    customerConfirmed: true,
    riderNotifyReady: true,
  };
}

async function tryAssignRiderToOrder(orderRef, orderData, context = {}) {
  const riderSearch = await findRiderForOrder(orderData);
  const assignedRider = riderSearch.rider;
  if (!assignedRider?.riderId) {
    return {
      matched: false,
      orderId: orderRef.id,
      reason: riderSearch.reason || 'no_eligible_rider',
    };
  }

  const riderId = assignedRider.riderId;
  let assigned = false;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) {
      return;
    }
    const current = snap.data() || {};
    if (!isOrderEligibleForRiderMatch(current)) {
      return;
    }

    tx.update(orderRef, {
      status: 'pending',
      statusLabel: 'pending_customer_confirmation',
      driverId: riderId,
      driverName: null,
      driverPhone: null,
      assignedRiderAt: FieldValue.serverTimestamp(),
      reassignedAt: FieldValue.serverTimestamp(),
      needsReassign: false,
      reassignFailureReason: FieldValue.delete(),
      reassignReason: FieldValue.delete(),
      reassignRequestedAt: FieldValue.delete(),
      riderNotifyReady: true,
      riderSearch: buildRiderSearchPatch(riderSearch, assignedRider),
      updatedAt: FieldValue.serverTimestamp(),
    });
    assigned = true;
  });

  if (!assigned) {
    return {
      matched: false,
      orderId: orderRef.id,
      reason: 'order_no_longer_eligible',
    };
  }

  try {
    await db.collection('app_notifications').add(
      buildRiderNotificationPayload({
        orderId: orderRef.id,
        orderData,
        riderId,
      }),
    );
  } catch (error) {
    logger.warn('pending_order_rider_match notification failed', {
      orderId: orderRef.id,
      riderId,
      message: error instanceof Error ? error.message : String(error),
    });
  }

  try {
    await orderRef.collection('timeline').add({
      event: 'rider_auto_assigned',
      eventLabel: 'ระบบจับคู่ไรเดอร์อัตโนมัติ',
      orderId: orderRef.id,
      riderId,
      actorRole: 'system',
      actorId: 'pending_order_rider_match',
      triggerReason: context.reason || 'auto_match',
      ...(context.triggerRiderId ? { triggerRiderId: context.triggerRiderId } : {}),
      timestamp: FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Timeline logging must not fail the assignment.
  }

  return {
    matched: true,
    orderId: orderRef.id,
    riderId,
  };
}

async function matchPendingAwaitingRiderOrders(context = {}) {
  if (!db || !findNearestRiderForShop) {
    throw new Error('pending_order_rider_match not initialized');
  }

  const snapshot = await db
    .collection('orders')
    .where('status', '==', 'awaiting_rider')
    .limit(MAX_ORDERS_PER_RUN)
    .get();

  if (snapshot.empty) {
    return { scanned: 0, matched: 0, skipped: 0, failures: 0 };
  }

  const docs = [...snapshot.docs].sort((a, b) => {
    const aMs = a.data()?.createdAt?.toMillis?.() ?? 0;
    const bMs = b.data()?.createdAt?.toMillis?.() ?? 0;
    return aMs - bMs;
  });

  let matched = 0;
  let skipped = 0;
  let failures = 0;

  for (const doc of docs) {
    const data = doc.data() || {};
    if (!isOrderEligibleForRiderMatch(data)) {
      skipped += 1;
      continue;
    }

    try {
      const result = await tryAssignRiderToOrder(doc.ref, data, context);
      if (result.matched) {
        matched += 1;
      } else {
        skipped += 1;
      }
    } catch (error) {
      failures += 1;
      logger.error('pending_order_rider_match assign failed', {
        orderId: doc.id,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const summary = {
    scanned: docs.length,
    matched,
    skipped,
    failures,
    reason: context.reason || 'manual',
    ...(context.triggerRiderId ? { triggerRiderId: context.triggerRiderId } : {}),
  };

  if (matched > 0) {
    logger.info('pending_order_rider_match completed', summary);
  }

  return summary;
}

function registerHandlers({ onSchedule, DEFAULT_REGION }) {
  const matchPendingAwaitingRiderOrdersScheduled = onSchedule(
    {
      schedule: 'every 2 minutes',
      region: DEFAULT_REGION,
    },
    async () => {
      try {
        await matchPendingAwaitingRiderOrders({ reason: 'scheduled' });
      } catch (error) {
        logger.error('matchPendingAwaitingRiderOrdersScheduled failed', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
    },
  );

  return {
    matchPendingAwaitingRiderOrdersScheduled,
  };
}

module.exports = {
  init,
  registerHandlers,
  matchPendingAwaitingRiderOrders,
  isOrderEligibleForRiderMatch,
};
