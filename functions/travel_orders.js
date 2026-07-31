const OMISE_PAYMENT_METHODS = new Set([
  'omise_promptpay',
  'omise_card',
  'omise_mobile_banking',
  'omise_truemoney',
]);

const TRAVEL_VEHICLE_MULTIPLIERS = {
  motorcycle: 1.0,
  sedan: 1.25,
  pickup: 1.45,
};

const { RIDER_AVAILABILITY_DOC_PATH } = require('./rider_availability');

function buildOrderCode(prefix, orderId, now = new Date()) {
  const y = String(now.getFullYear()).padStart(4, '0');
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const suffix = String(orderId).substring(0, 6).toUpperCase();
  return `${prefix}-${y}${m}${d}-${suffix}`;
}

function assertNonAnonymous(request, HttpsError) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนสร้างออเดอร์');
  }
  const provider = request.auth.token?.firebase?.sign_in_provider;
  if (provider === 'anonymous') {
    throw new HttpsError(
      'failed-precondition',
      'กรุณาเข้าสู่ระบบด้วยบัญชีจริงก่อนสั่งเดินทาง',
    );
  }
}

function computeTravelDistanceFee(distanceKm, rates, parseNumber) {
  const normalizedKm = Number.isFinite(distanceKm) && distanceKm >= 0 ? distanceKm : 0;
  const minBillableKm = parseNumber(rates?.travelMinBillableKm ?? 1);
  const billableKm = normalizedKm < minBillableKm ? minBillableKm : normalizedKm;
  const baseFee = parseNumber(rates?.travelBaseFee ?? 25);
  const perKmFee = parseNumber(rates?.travelPerKmFee ?? 12.5);
  // Match van2 ShippingPricingPolicy._computeDistanceFee / computeShippingFeeByDistance.
  return baseFee + (billableKm - minBillableKm) * perKmFee;
}

function computeTravelFareForVehicle(distanceKm, vehicleType, rates, parseNumber) {
  const baseFare = computeTravelDistanceFee(distanceKm, rates, parseNumber);
  const multiplier = TRAVEL_VEHICLE_MULTIPLIERS[vehicleType] ?? 1.0;
  return Math.round(baseFare * multiplier * 100) / 100;
}

function readRiderLatLng(data) {
  const geo = data?.currentLocation;
  if (geo?.latitude != null && geo?.longitude != null) {
    return { lat: Number(geo.latitude), lng: Number(geo.longitude) };
  }
  const lat = Number(data?.latitude);
  const lng = Number(data?.longitude);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    return { lat, lng };
  }
  return null;
}

function resolveTravelVehicleType(data) {
  const raw = String(
    data?.resolvedVehicleType || data?.vehicleType || '',
  ).trim().toLowerCase();
  if (raw.includes('motor') || raw === 'motorcycle') return 'motorcycle';
  if (raw.includes('sedan') || raw.includes('car') || raw === 'sedan') return 'sedan';
  if (raw.includes('pickup') || raw.includes('truck') || raw === 'pickup') return 'pickup';
  return null;
}

function isTravelRiderAvailable(data) {
  if (data?.passengerReady !== true && data?.onlineReady !== true) {
    return false;
  }
  const locationStatus = String(data?.locationStatus || '').trim().toLowerCase();
  if (locationStatus === 'offline') {
    return false;
  }
  const coords = readRiderLatLng(data);
  if (!coords || (coords.lat === 0 && coords.lng === 0)) {
    return false;
  }
  const updatedAt = data?.locationUpdatedAt?.toDate?.() || data?.updatedAt?.toDate?.();
  if (!updatedAt) {
    return true;
  }
  return Date.now() - updatedAt.getTime() <= 10 * 60 * 1000;
}

async function getTravelRidersEntries(db) {
  try {
    const poolDoc = await db.doc(RIDER_AVAILABILITY_DOC_PATH).get();
    const travelRiders = poolDoc.data()?.travelRiders || {};
    return Object.entries(travelRiders).map(([riderId, data]) => ({
      riderId,
      data: data || {},
    }));
  } catch (_) {
    return [];
  }
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadiusM = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return (earthRadiusM * c) / 1000;
}

async function resolveBillableTravelDistanceKm(
  clientKm,
  pickupLat,
  pickupLng,
  destLat,
  destLng,
  deps,
) {
  const straightLineKm = haversineKm(pickupLat, pickupLng, destLat, destLng);
  if (!Number.isFinite(clientKm) || clientKm < 0) {
    return { ok: false, reason: 'invalid_client_distance' };
  }

  let routeKm = null;
  if (typeof deps?.fetchDrivingRouteKm === 'function') {
    routeKm = await deps.fetchDrivingRouteKm(pickupLat, pickupLng, destLat, destLng);
  }

  const fallbackKm = Math.max(straightLineKm * 1.25, straightLineKm);
  const hasRouteKm = Number.isFinite(routeKm) && routeKm > 0;
  const authoritativeKm = hasRouteKm ? routeKm : fallbackKm;
  const toleranceKm = Math.max(0.5, authoritativeKm * 0.1);

  if (hasRouteKm) {
    const billableKm = Math.max(authoritativeKm, straightLineKm);
    if (clientKm + toleranceKm < billableKm * 0.92) {
      return {
        ok: false,
        reason: 'distance_under_reported',
        straightLineKm,
        routeKm,
        billableKm,
        clientKm,
      };
    }
    if (clientKm - toleranceKm > billableKm * 1.12) {
      return {
        ok: false,
        reason: 'distance_over_reported',
        straightLineKm,
        routeKm,
        billableKm,
        clientKm,
      };
    }
    return {
      ok: true,
      billableKm,
      clientKm,
      straightLineKm,
      routeKm,
      source: 'google_directions',
    };
  }

  // Directions unavailable on server — align with client route distance within bounds.
  const minKm = Math.max(straightLineKm * 0.9, straightLineKm);
  const maxKm = straightLineKm * 2.5 + 2;
  if (clientKm < minKm || clientKm > maxKm) {
    return {
      ok: false,
      reason: 'distance_out_of_bounds',
      straightLineKm,
      clientKm,
    };
  }
  return {
    ok: true,
    billableKm: clientKm,
    clientKm,
    straightLineKm,
    routeKm: null,
    source: 'client_route_fallback',
  };
}

async function findNearestTravelRider(db, pickupLat, pickupLng, vehicleType) {
  const entries = await getTravelRidersEntries(db);
  const excludedBreakdown = {};
  const addExcluded = (reason) => {
    excludedBreakdown[reason] = (excludedBreakdown[reason] || 0) + 1;
  };

  const candidates = [];
  const fallbackCandidates = [];

  for (const entry of entries) {
    const data = entry.data;
    if (!isTravelRiderAvailable(data)) {
      addExcluded('not_travel_available');
      continue;
    }
    if (resolveTravelVehicleType(data) !== vehicleType) {
      addExcluded('vehicle_type_mismatch');
      continue;
    }
    const coords = readRiderLatLng(data);
    if (!coords) {
      addExcluded('missing_coordinates');
      continue;
    }
    const distanceKm = haversineKm(pickupLat, pickupLng, coords.lat, coords.lng);
    const riderDistance = { riderId: entry.riderId, distanceKm };
    fallbackCandidates.push(riderDistance);

    const updatedAt = data.locationUpdatedAt?.toDate?.() || data.updatedAt?.toDate?.();
    if (updatedAt && Date.now() - updatedAt.getTime() > 10 * 60 * 1000) {
      addExcluded('stale_location');
      continue;
    }
    candidates.push(riderDistance);
  }

  const base = {
    onlineRiderCount: entries.length,
    excludedBreakdown,
  };

  if (candidates.length === 0) {
    if (fallbackCandidates.length === 1) {
      return {
        ...base,
        rider: fallbackCandidates[0],
        searchedRadiusKm: 10,
        eligibleRiderCount: 1,
        excludedRiderCount: Math.max(0, entries.length - 1),
        reason: 'single_travel_ready_fallback',
      };
    }
    return {
      ...base,
      rider: null,
      searchedRadiusKm: 10,
      eligibleRiderCount: 0,
      excludedRiderCount: entries.length,
      reason: entries.length === 0 ? 'no_travel_ready_riders' : 'no_eligible_travel_riders',
    };
  }

  for (let radiusKm = 2; radiusKm <= 10; radiusKm += 2) {
    const inRadius = candidates
      .filter((c) => c.distanceKm <= radiusKm)
      .sort((a, b) => a.distanceKm - b.distanceKm);
    if (inRadius.length > 0) {
      return {
        ...base,
        rider: inRadius[0],
        searchedRadiusKm: radiusKm,
        eligibleRiderCount: candidates.length,
        excludedRiderCount: entries.length - candidates.length,
      };
    }
  }

  const nearest = [...candidates].sort((a, b) => a.distanceKm - b.distanceKm)[0];
  return {
    ...base,
    rider: nearest,
    searchedRadiusKm: 10,
    eligibleRiderCount: candidates.length,
    excludedRiderCount: entries.length - candidates.length,
    reason: 'outside_search_radius_fallback',
  };
}

async function quoteTravelFareHandler(request, deps) {
  const { HttpsError, parseNumber, getPricingRates } = deps;

  assertNonAnonymous(request, HttpsError);

  const data = request.data || {};
  const pickup = data.pickup || {};
  const destination = data.destination || {};
  const pickupLat = parseNumber(pickup.latitude);
  const pickupLng = parseNumber(pickup.longitude);
  const destLat = parseNumber(destination.latitude);
  const destLng = parseNumber(destination.longitude);
  const distanceKm = parseNumber(data.distanceKm);
  const vehicleType = String(data.vehicleType || 'motorcycle').trim().toLowerCase();

  if (!Number.isFinite(pickupLat) || !Number.isFinite(pickupLng)) {
    throw new HttpsError('invalid-argument', 'พิกัดต้นทางไม่ถูกต้อง');
  }
  if (!Number.isFinite(destLat) || !Number.isFinite(destLng)) {
    throw new HttpsError('invalid-argument', 'พิกัดปลายทางไม่ถูกต้อง');
  }

  const distanceCheck = await resolveBillableTravelDistanceKm(
    distanceKm,
    pickupLat,
    pickupLng,
    destLat,
    destLng,
    deps,
  );
  if (!distanceCheck.ok) {
    throw new HttpsError(
      'invalid-argument',
      'ระยะทางไม่ถูกต้อง กรุณาคำนวณเส้นทางใหม่',
    );
  }
  if (!['motorcycle', 'sedan', 'pickup'].includes(vehicleType)) {
    throw new HttpsError('invalid-argument', 'ประเภทรถไม่รองรับ');
  }

  const rates = await getPricingRates();
  const billableDistanceKm = distanceCheck.billableKm;
  const fare = computeTravelFareForVehicle(
    billableDistanceKm,
    vehicleType,
    rates,
    parseNumber,
  );

  return {
    fare,
    billableDistanceKm,
    clientDistanceKm: distanceKm,
    vehicleType,
    distanceSource: distanceCheck.source || null,
  };
}

async function createTravelOrderHandler(request, deps) {
  const { db, admin, FieldValue, HttpsError, parseNumber, getPricingRates } = deps;

  assertNonAnonymous(request, HttpsError);

  const uid = request.auth.uid;
  const data = request.data || {};
  const pickup = data.pickup || {};
  const destination = data.destination || {};
  const pickupLat = parseNumber(pickup.latitude);
  const pickupLng = parseNumber(pickup.longitude);
  const destLat = parseNumber(destination.latitude);
  const destLng = parseNumber(destination.longitude);
  const distanceKm = parseNumber(data.distanceKm);
  const vehicleType = String(data.vehicleType || 'motorcycle').trim().toLowerCase();

  if (!Number.isFinite(pickupLat) || !Number.isFinite(pickupLng)) {
    throw new HttpsError('invalid-argument', 'พิกัดต้นทางไม่ถูกต้อง');
  }
  if (!Number.isFinite(destLat) || !Number.isFinite(destLng)) {
    throw new HttpsError('invalid-argument', 'พิกัดปลายทางไม่ถูกต้อง');
  }
  const distanceCheck = await resolveBillableTravelDistanceKm(
    distanceKm,
    pickupLat,
    pickupLng,
    destLat,
    destLng,
    deps,
  );
  if (!distanceCheck.ok) {
    throw new HttpsError(
      'invalid-argument',
      'ระยะทางไม่ถูกต้อง กรุณาคำนวณเส้นทางใหม่',
    );
  }
  const billableDistanceKm = distanceCheck.billableKm;
  if (!['motorcycle', 'sedan', 'pickup'].includes(vehicleType)) {
    throw new HttpsError('invalid-argument', 'ประเภทรถไม่รองรับ');
  }

  const paymentMethod = String(data.paymentMethod || '').trim();
  const paymentStatus = String(data.paymentStatus || '').trim();
  const paymentSessionId = String(data.paymentSessionId || '').trim();
  const allowedStatuses = ['cash_on_delivery', 'verified'];
  if (!allowedStatuses.includes(paymentStatus)) {
    throw new HttpsError('invalid-argument', 'สถานะชำระเงินไม่รองรับ');
  }

  const rates = await getPricingRates();
  const fare = computeTravelFareForVehicle(billableDistanceKm, vehicleType, rates, parseNumber);

  let omiseChargeId = null;
  if (paymentStatus === 'verified') {
    if (!OMISE_PAYMENT_METHODS.has(paymentMethod)) {
      throw new HttpsError('invalid-argument', 'ช่องทางชำระเงินไม่รองรับ');
    }
    if (!paymentSessionId) {
      throw new HttpsError('invalid-argument', 'ต้องมี paymentSessionId');
    }
  }

  const idempotencyKey = String(data.idempotencyKey || '').trim();
  const claimRef = idempotencyKey
    ? db.collection('travel_order_claims').doc(`${uid}_${idempotencyKey}`)
    : null;

  if (claimRef) {
    const existing = await claimRef.get();
    if (existing.exists) {
      const claim = existing.data() || {};
      return {
        orderIds: Array.isArray(claim.orderIds) ? claim.orderIds : [],
        combinedGrandTotal: parseNumber(claim.combinedGrandTotal),
        hasAssignedRider: claim.hasAssignedRider === true,
      };
    }
  }

  const userRecord = await admin.auth().getUser(uid);
  const notifyRider = data.notifyRider === true;
  const riderNotifyReady = data.riderNotifyReady === true;
  const isVerifiedPayment = paymentStatus === 'verified';
  const riderSearch = await findNearestTravelRider(db, pickupLat, pickupLng, vehicleType);
  const assignedRider = riderSearch.rider;
  const hasAssignedRider = assignedRider != null;
  const shouldAssignRiderImmediately = notifyRider && hasAssignedRider;

  const orderRef = db.collection('orders').doc();
  const now = new Date();
  const orderCode = buildOrderCode('TRV', orderRef.id, now);

  const initialOrderStatus = isVerifiedPayment
    ? hasAssignedRider
      ? 'pending'
      : 'awaiting_rider'
    : hasAssignedRider
      ? notifyRider
        ? 'pending'
        : 'awaiting_payment_slip_review'
      : notifyRider
        ? 'awaiting_rider'
        : 'awaiting_payment_slip_review';

  const initialStatusLabel = isVerifiedPayment
    ? hasAssignedRider
      ? 'pending_customer_confirmation'
      : 'awaiting_nearest_rider'
    : hasAssignedRider
      ? notifyRider
        ? 'pending_customer_confirmation'
        : 'awaiting_payment_slip_review'
      : notifyRider
        ? 'awaiting_nearest_rider'
        : 'awaiting_payment_slip_review';

  const scheduledAtRaw = data.scheduledAt;
  let scheduledAt = admin.firestore.Timestamp.now();
  if (scheduledAtRaw) {
    const parsed = new Date(scheduledAtRaw);
    if (!Number.isNaN(parsed.getTime())) {
      scheduledAt = admin.firestore.Timestamp.fromDate(parsed);
    }
  }

  const orderPayload = {
    orderId: orderRef.id,
    orderCode,
    orderType: 'travel_passenger',
    serviceType: 'travel_passenger',
    status: initialOrderStatus,
    statusLabel: initialStatusLabel,
    customerConfirmed: true,
    customerConfirmedAt: FieldValue.serverTimestamp(),
    riderNotifyReady: isVerifiedPayment ? hasAssignedRider : riderNotifyReady,
    paymentMethod,
    paymentMethodLabel: String(data.paymentMethodLabel || paymentMethod).trim(),
    paymentStatus,
    paymentStatusLabel: String(data.paymentStatusLabel || paymentStatus).trim(),
    sourceApp: 'van2_customer',
    customerId: uid,
    customerEmail: userRecord.email || null,
    customerPhone: userRecord.phoneNumber || null,
    customerSnapshot: {
      uid,
      email: userRecord.email || null,
      phoneNumber: userRecord.phoneNumber || null,
    },
    shopOwnerId: 'travel_service',
    shopId: 'travel_service',
    shopName: String(pickup.title || 'จุดรับ').trim(),
    shopAddress: String(pickup.subtitle || '').trim(),
    shopLatitude: pickupLat,
    shopLongitude: pickupLng,
    driverId: shouldAssignRiderImmediately ? assignedRider.riderId : null,
    driverName: null,
    driverPhone: null,
    assignedRiderAt: shouldAssignRiderImmediately ? FieldValue.serverTimestamp() : null,
    customerLocation: {
      latitude: destLat,
      longitude: destLng,
      label: String(destination.title || 'ปลายทาง').trim(),
    },
    deliverySnapshot: {
      latitude: destLat,
      longitude: destLng,
      locationLabel: String(destination.title || 'ปลายทาง').trim(),
    },
    itemCount: 1,
    totalQuantity: 1,
    products: [
      {
        productId: 'travel_passenger_service',
        name: 'บริการรับส่งผู้โดยสาร',
        quantity: 1,
        unitPrice: fare,
        lineTotal: fare,
        note: `จาก ${String(pickup.title || '')} ไป ${String(destination.title || '')}`,
      },
    ],
    totalPrice: fare,
    subtotal: fare,
    shippingFee: 0,
    grandTotal: fare,
    travelRequest: {
      pickup: {
        latitude: pickupLat,
        longitude: pickupLng,
        title: String(pickup.title || '').trim(),
        subtitle: String(pickup.subtitle || '').trim(),
      },
      destination: {
        latitude: destLat,
        longitude: destLng,
        title: String(destination.title || '').trim(),
        subtitle: String(destination.subtitle || '').trim(),
      },
      distanceKm: billableDistanceKm,
      vehicleType,
      vehicleTypeLabel: String(data.vehicleTypeLabel || vehicleType).trim(),
      scheduledAt,
      scheduleLabel: String(data.scheduleLabel || '').trim(),
      isImmediate: data.isImmediate === true,
      fare,
    },
    riderSearch: {
      stepKm: 2,
      maxRadiusKm: 10,
      searchedRadiusKm: riderSearch.searchedRadiusKm,
      onlineRiderCount: riderSearch.onlineRiderCount,
      eligibleRiderCount: riderSearch.eligibleRiderCount,
      matched: hasAssignedRider,
      matchedRiderId: assignedRider?.riderId || null,
      matchedDistanceKm: assignedRider?.distanceKm ?? null,
      ...(riderSearch.excludedRiderCount > 0
        ? { excludedRiderCount: riderSearch.excludedRiderCount }
        : {}),
      ...(Object.keys(riderSearch.excludedBreakdown || {}).length > 0
        ? { excludedBreakdown: riderSearch.excludedBreakdown }
        : {}),
      ...(riderSearch.reason ? { reason: riderSearch.reason } : {}),
    },
    audit: {
      createdBy: uid,
      createdByRole: 'customer',
      createdSource: String(data.auditSource || 'cloud_function_travel').trim(),
    },
    timestamp: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (isVerifiedPayment && paymentSessionId) {
    orderPayload.paymentSessionId = paymentSessionId;
    orderPayload.paymentGroupId = paymentSessionId;
    orderPayload.paymentSubmittedAt = FieldValue.serverTimestamp();
    orderPayload.paymentVerification = {
      provider: 'omise',
      providerLabel: 'Omise',
      feedbackId: paymentSessionId,
      paymentGroupId: paymentSessionId,
      paymentSessionId,
      expectedCombinedAmount: fare,
      status: 'verified',
      statusLabel: 'ชำระเงินผ่าน Omise แล้ว',
      message: 'Omise charge successful',
      checkedAt: FieldValue.serverTimestamp(),
    };
  }

  await db.runTransaction(async (transaction) => {
    if (isVerifiedPayment && paymentSessionId) {
      const sessionRef = db.collection('payment_sessions').doc(paymentSessionId);
      const sessionSnap = await transaction.get(sessionRef);
      if (!sessionSnap.exists) {
        throw new HttpsError('failed-precondition', 'ไม่พบ payment session');
      }
      const session = sessionSnap.data() || {};
      if (String(session.uid || '') !== uid) {
        throw new HttpsError('permission-denied', 'payment session ไม่ตรงกับผู้ใช้');
      }
      if (session.status !== 'paid') {
        throw new HttpsError('failed-precondition', 'การชำระเงินยังไม่สำเร็จ');
      }
      if (session.consumed === true) {
        throw new HttpsError('failed-precondition', 'payment session ถูกใช้แล้ว');
      }
      if (String(session.channel || '') !== paymentMethod) {
        throw new HttpsError('failed-precondition', 'ช่องทางชำระเงินไม่ตรงกับ session');
      }
      const sessionAmount = parseNumber(session.amount);
      if (Math.abs(sessionAmount - fare) > 0.01) {
        throw new HttpsError('failed-precondition', 'ยอดชำระ Omise ไม่ตรงกับค่าเดินทาง');
      }
      omiseChargeId = String(session.omiseChargeId || '').trim() || null;
      if (omiseChargeId) {
        orderPayload.paymentVerification.omiseChargeId = omiseChargeId;
      }
      transaction.set(
        sessionRef,
        {
          consumed: true,
          consumedAt: FieldValue.serverTimestamp(),
          orderIds: [orderRef.id],
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    if (claimRef) {
      transaction.set(claimRef, {
        uid,
        orderIds: [orderRef.id],
        combinedGrandTotal: fare,
        hasAssignedRider,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    transaction.set(orderRef, orderPayload);
  });

  const timelineRef = orderRef.collection('timeline').doc();
  await timelineRef.set({
    event: 'order_created',
    eventLabel: String(data.createdEventLabel || 'ลูกค้าสร้างออเดอร์').trim(),
    actorId: uid,
    actorRole: 'customer',
    orderId: orderRef.id,
    orderCode,
    status: initialOrderStatus,
    timestamp: FieldValue.serverTimestamp(),
  });

  if (notifyRider && assignedRider) {
    await db.collection('app_notifications').add({
      targetApp: 'van3',
      recipientUid: assignedRider.riderId,
      orderId: orderRef.id,
      title: isVerifiedPayment ? 'ชำระเงินแล้ว มีงานเดินทางใหม่' : 'มีคำขอเดินทางใหม่',
      body: orderCode
        ? isVerifiedPayment
          ? `งานเดินทาง ${orderCode} ชำระเงินแล้ว`
          : `งานเดินทาง ${orderCode} จาก ${String(pickup.title || '')}`
        : `มีงานเดินทางใหม่จาก ${String(pickup.title || '')}`,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
      source: 'van2_customer',
      sourceApp: 'van2_customer',
      action: isVerifiedPayment ? 'order_payment_verified' : 'travel_order_created_customer_confirmed',
      customerConfirmed: true,
      riderNotifyReady: isVerifiedPayment ? true : riderNotifyReady,
    });
  }

  return {
    orderIds: [orderRef.id],
    combinedGrandTotal: fare,
    hasAssignedRider,
    orderCode,
  };
}

module.exports = {
  createTravelOrderHandler,
  quoteTravelFareHandler,
  assertNonAnonymous,
  computeTravelFareForVehicle,
  findNearestTravelRider,
};
