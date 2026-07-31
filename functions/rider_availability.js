const RIDER_AVAILABILITY_DOC_PATH = 'system/rider_availability';
const RIDER_FRESH_LOCATION_MS = 10 * 60 * 1000;

const AVAILABILITY_FIELD_KEYS = [
  'onlineReady',
  'passengerReady',
  'vehicleType',
  'locationStatus',
];

const DISPLAY_FIELD_KEYS = [
  'displayName',
  'rating',
  'profileImageUrl',
  'photoURL',
  'licensePlate',
];

function maskLicensePlate(raw) {
  const value = String(raw || '').trim();
  if (!value) {
    return '';
  }
  if (value.length <= 3) {
    return value;
  }
  return `***${value.slice(-3)}`;
}

function readRiderLatLng(data) {
  const geo = data?.currentLocation;
  if (geo && Number.isFinite(Number(geo.latitude)) && Number.isFinite(Number(geo.longitude))) {
    return { lat: Number(geo.latitude), lng: Number(geo.longitude) };
  }
  const lat = Number(data?.latitude);
  const lng = Number(data?.longitude);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    return { lat, lng };
  }
  return null;
}

function isLocationFresh(data) {
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
  return Date.now() - updatedAt.getTime() <= RIDER_FRESH_LOCATION_MS;
}

function isTravelAvailable(data) {
  if (data?.passengerReady !== true && data?.onlineReady !== true) {
    return false;
  }
  return isLocationFresh(data);
}

function isDeliveryOnline(data) {
  return data?.onlineReady === true && isLocationFresh(data);
}

function resolveTravelVehicleType(data) {
  const rawCandidates = [
    data?.vehicleType,
    data?.vehicle_type,
    data?.vehicle,
    data?.vehicleCategory,
  ];
  for (const rawValue of rawCandidates) {
    const normalized = String(rawValue || '').trim().toLowerCase();
    if (!normalized) {
      continue;
    }
    if (
      normalized.includes('motor') ||
      normalized.includes('bike') ||
      normalized.includes('motorcycle') ||
      normalized.includes('มอเตอร์')
    ) {
      return 'motorcycle';
    }
    if (
      normalized.includes('pickup') ||
      normalized.includes('truck') ||
      normalized.includes('กระบะ')
    ) {
      return 'pickup';
    }
    if (
      normalized.includes('sedan') ||
      normalized.includes('car') ||
      normalized.includes('เก๋ง')
    ) {
      return 'sedan';
    }
    if (normalized === 'motorcycle' || normalized === 'bike' || normalized === 'motorbike') {
      return 'motorcycle';
    }
    if (normalized === 'sedan') {
      return 'sedan';
    }
    if (normalized === 'pickup') {
      return 'pickup';
    }
  }
  if (isTravelAvailable(data)) {
    return 'motorcycle';
  }
  return null;
}

function buildMinimalRiderEntry(data) {
  const coords = readRiderLatLng(data);
  const resolvedVehicleType = resolveTravelVehicleType(data);
  const entry = {
    onlineReady: data?.onlineReady === true,
    passengerReady: data?.passengerReady === true,
    vehicleType: String(data?.vehicleType || '').trim(),
    locationStatus: String(data?.locationStatus || '').trim(),
  };

  const displayName = String(data?.displayName || data?.name || '').trim();
  if (displayName) {
    entry.displayName = displayName;
  }

  const rating = Number(data?.rating);
  if (Number.isFinite(rating)) {
    entry.rating = rating;
  }

  const profileImageUrl = String(
    data?.profileImageUrl || data?.photoURL || '',
  ).trim();
  if (profileImageUrl) {
    entry.profileImageUrl = profileImageUrl;
  }

  if (resolvedVehicleType) {
    entry.resolvedVehicleType = resolvedVehicleType;
  }

  const licensePlate = maskLicensePlate(data?.licensePlate);
  if (licensePlate) {
    entry.licensePlate = licensePlate;
  }

  if (coords) {
    entry.latitude = coords.lat;
    entry.longitude = coords.lng;
    entry.currentLocation = { latitude: coords.lat, longitude: coords.lng };
  }
  const updatedAt = data?.locationUpdatedAt || data?.updatedAt;
  if (updatedAt) {
    entry.locationUpdatedAt = updatedAt;
  }
  return entry;
}

function recalculateCounts(pool) {
  const deliveryRiders = pool.deliveryRiders || {};
  const travelRiders = pool.travelRiders || {};
  pool.deliveryOnlineCount = Object.keys(deliveryRiders).length;
  const counts = { motorcycle: 0, sedan: 0, pickup: 0 };
  for (const entry of Object.values(travelRiders)) {
    const vehicleType = resolveTravelVehicleType(entry);
    if (vehicleType) {
      counts[vehicleType] = (counts[vehicleType] || 0) + 1;
    }
  }
  pool.travelVehicleCounts = counts;
}

function emptyPool(FieldValue) {
  return {
    deliveryRiders: {},
    travelRiders: {},
    deliveryOnlineCount: 0,
    travelVehicleCounts: { motorcycle: 0, sedan: 0, pickup: 0 },
    updatedAt: FieldValue.serverTimestamp(),
    rebuiltAt: FieldValue.serverTimestamp(),
  };
}

function availabilityFieldsChanged(before, after) {
  for (const key of AVAILABILITY_FIELD_KEYS) {
    const beforeValue = before?.[key];
    const afterValue = after?.[key];
    if (Boolean(beforeValue) !== Boolean(afterValue)) {
      return true;
    }
    if (String(beforeValue ?? '') !== String(afterValue ?? '')) {
      return true;
    }
  }
  return false;
}

function displayFieldsChanged(before, after) {
  for (const key of DISPLAY_FIELD_KEYS) {
    const beforeValue = before?.[key];
    const afterValue = after?.[key];
    if (String(beforeValue ?? '') !== String(afterValue ?? '')) {
      return true;
    }
  }
  return false;
}

function locationFieldsChanged(before, after) {
  const beforeCoords = readRiderLatLng(before);
  const afterCoords = readRiderLatLng(after);
  if (!beforeCoords && afterCoords) {
    return true;
  }
  if (beforeCoords && !afterCoords) {
    return true;
  }
  if (beforeCoords && afterCoords) {
    if (Math.abs(beforeCoords.lat - afterCoords.lat) > 0.00001) {
      return true;
    }
    if (Math.abs(beforeCoords.lng - afterCoords.lng) > 0.00001) {
      return true;
    }
  }

  const beforeTs = before?.locationUpdatedAt?.toMillis?.() ?? 0;
  const afterTs = after?.locationUpdatedAt?.toMillis?.() ?? 0;
  return beforeTs !== afterTs;
}

function poolRelevantFieldsChanged(before, after) {
  return (
    availabilityFieldsChanged(before, after) ||
    locationFieldsChanged(before, after) ||
    displayFieldsChanged(before, after)
  );
}

async function patchRiderInPool(db, FieldValue, riderId, data) {
  const ref = db.doc(RIDER_AVAILABILITY_DOC_PATH);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const pool = snapshot.exists
      ? { ...snapshot.data() }
      : emptyPool(FieldValue);
    pool.deliveryRiders = { ...(pool.deliveryRiders || {}) };
    pool.travelRiders = { ...(pool.travelRiders || {}) };

    if (isDeliveryOnline(data)) {
      pool.deliveryRiders[riderId] = buildMinimalRiderEntry(data);
    } else {
      delete pool.deliveryRiders[riderId];
    }

    if (isTravelAvailable(data)) {
      pool.travelRiders[riderId] = buildMinimalRiderEntry(data);
    } else {
      delete pool.travelRiders[riderId];
    }

    recalculateCounts(pool);
    pool.updatedAt = FieldValue.serverTimestamp();
    transaction.set(ref, pool);
  });
}

async function removeRiderFromPool(db, FieldValue, riderId) {
  const ref = db.doc(RIDER_AVAILABILITY_DOC_PATH);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      return;
    }
    const pool = { ...snapshot.data() };
    pool.deliveryRiders = { ...(pool.deliveryRiders || {}) };
    pool.travelRiders = { ...(pool.travelRiders || {}) };
    delete pool.deliveryRiders[riderId];
    delete pool.travelRiders[riderId];
    recalculateCounts(pool);
    pool.updatedAt = FieldValue.serverTimestamp();
    transaction.set(ref, pool);
  });
}

async function rebuildRiderAvailabilityPool(db, FieldValue) {
  const [onlineSnapshot, passengerSnapshot] = await Promise.all([
    db.collection('riders').where('onlineReady', '==', true).get(),
    db.collection('riders').where('passengerReady', '==', true).get(),
  ]);

  const merged = new Map();
  for (const doc of onlineSnapshot.docs) {
    merged.set(doc.id, doc.data() || {});
  }
  for (const doc of passengerSnapshot.docs) {
    const existing = merged.get(doc.id) || {};
    merged.set(doc.id, { ...existing, ...(doc.data() || {}) });
  }

  const pool = emptyPool(FieldValue);
  for (const [riderId, data] of merged.entries()) {
    if (isDeliveryOnline(data)) {
      pool.deliveryRiders[riderId] = buildMinimalRiderEntry(data);
    }
    if (isTravelAvailable(data)) {
      pool.travelRiders[riderId] = buildMinimalRiderEntry(data);
    }
  }
  recalculateCounts(pool);
  await db.doc(RIDER_AVAILABILITY_DOC_PATH).set(pool);
  return pool;
}

function snapshotFromPool(pool) {
  const deliveryRiders = pool?.deliveryRiders || {};
  const docs = Object.entries(deliveryRiders).map(([id, data]) => ({
    id,
    data: () => data,
  }));
  return {
    size: docs.length,
    docs,
    empty: docs.length === 0,
  };
}

function createRiderAvailabilityHandlers({
  db,
  FieldValue,
  logger,
  onSchedule,
  onDocumentWritten,
  DEFAULT_REGION,
}) {
  const syncRiderAvailabilityOnWrite = onDocumentWritten(
    {
      document: 'riders/{riderId}',
      region: DEFAULT_REGION,
    },
    async (event) => {
      const riderId = event.params.riderId;
      const afterExists = event.data?.after?.exists;
      const beforeExists = event.data?.before?.exists;
      const after = afterExists ? event.data.after.data() : null;
      const before = beforeExists ? event.data.before.data() : null;

      try {
        if (!afterExists) {
          await removeRiderFromPool(db, FieldValue, riderId);
          return;
        }

        if (beforeExists && !poolRelevantFieldsChanged(before, after)) {
          return;
        }

        await patchRiderInPool(db, FieldValue, riderId, after);
      } catch (error) {
        logger.error('syncRiderAvailabilityOnWrite failed', {
          riderId,
          message: error instanceof Error ? error.message : String(error),
        });
      }
    },
  );

  const refreshRiderAvailabilityPoolScheduled = onSchedule(
    {
      schedule: 'every 2 minutes',
      region: DEFAULT_REGION,
    },
    async () => {
      try {
        await rebuildRiderAvailabilityPool(db, FieldValue);
      } catch (error) {
        logger.error('refreshRiderAvailabilityPoolScheduled failed', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
    },
  );

  return {
    syncRiderAvailabilityOnWrite,
    refreshRiderAvailabilityPoolScheduled,
  };
}

module.exports = {
  RIDER_AVAILABILITY_DOC_PATH,
  RIDER_FRESH_LOCATION_MS,
  snapshotFromPool,
  rebuildRiderAvailabilityPool,
  createRiderAvailabilityHandlers,
};
