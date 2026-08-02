const MERCHANT_GP_RATE = 0.18;
const CHECKOUT_QUOTES_COLLECTION = 'checkout_quotes';
const CHECKOUT_QUOTE_TTL_MS = 30 * 60 * 1000;
const DEFAULT_NATIONWIDE_BASE_FEE = 45;
const DEFAULT_NATIONWIDE_PER_KG_FEE = 18;
const DEFAULT_NATIONWIDE_REMOTE_SURCHARGE = 30;
const RIDER_FRESH_LOCATION_MINUTES = 10;
const ONLINE_RIDERS_CACHE_TTL_MS = 45 * 1000;
const RIDER_POOL_MAX_AGE_MS = 2 * 60 * 1000;

const {
  RIDER_AVAILABILITY_DOC_PATH,
  snapshotFromPool,
} = require('./rider_availability');

const VAN2_CART_SESSION_COLLECTION = 'van2_cart_sessions';
const SLIPOK_FEEDBACK_COLLECTION = 'slipok_feedback';

function slipAmountsMatch(actualAmount, expectedAmount) {
  const actual = Number(actualAmount);
  const expected = Number(expectedAmount);
  if (!Number.isFinite(actual) || !Number.isFinite(expected)) {
    return false;
  }
  return Math.abs(actual - expected) < 0.01;
}

async function loadVerifiedStandaloneSlipFeedback(
  db,
  HttpsError,
  {
    uid,
    verificationFeedbackId,
    paymentGroupId,
    slipStoragePath,
    expectedCombinedAmount,
  },
) {
  const feedbackRef = db.collection(SLIPOK_FEEDBACK_COLLECTION).doc(verificationFeedbackId);
  const feedbackDoc = await feedbackRef.get();
  if (!feedbackDoc.exists) {
    throw new HttpsError(
      'failed-precondition',
      'ไม่พบหลักฐานการตรวจสลิป กรุณาส่งสลิปใหม่',
    );
  }

  const data = feedbackDoc.data() || {};
  if (String(data.status || '').trim() !== 'verified') {
    throw new HttpsError('failed-precondition', 'สลิปยังไม่ผ่านการตรวจสอบ');
  }
  if (String(data.customerUid || '').trim() !== uid) {
    throw new HttpsError('permission-denied', 'สลิปไม่ตรงกับบัญชีผู้ใช้');
  }
  if (String(data.paymentGroupId || '').trim() !== paymentGroupId) {
    throw new HttpsError('failed-precondition', 'ข้อมูลการชำระเงินไม่ตรงกับสลิป');
  }
  const storedPath = String(data.storagePath || '').trim();
  const requestedPath = String(slipStoragePath || '').trim();
  if (!storedPath || !requestedPath || storedPath !== requestedPath) {
    throw new HttpsError('failed-precondition', 'ไฟล์สลิปไม่ตรงกับที่ตรวจสอบแล้ว');
  }
  if (!slipAmountsMatch(data.expectedCombinedAmount, expectedCombinedAmount)) {
    throw new HttpsError('failed-precondition', 'ยอดชำระไม่ตรงกับสลิปที่ตรวจแล้ว');
  }

  const existingOrderIds = Array.isArray(data.orderIds) ? data.orderIds : [];
  if (existingOrderIds.length > 0) {
    throw new HttpsError('failed-precondition', 'สลิปนี้ถูกใช้สร้างออเดอร์แล้ว');
  }

  return feedbackRef;
}

async function markStandaloneSlipFeedbackConsumed(db, FieldValue, feedbackRef, orderIds) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(feedbackRef);
    if (!snapshot.exists) {
      throw new Error('missing_slip_feedback');
    }
    const data = snapshot.data() || {};
    const existingOrderIds = Array.isArray(data.orderIds) ? data.orderIds : [];
    if (existingOrderIds.length > 0) {
      throw new Error('slip_already_consumed');
    }
    transaction.update(feedbackRef, {
      orderIds,
      consumedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

function readFiniteProductStock(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  return Math.max(0, Math.floor(parsed));
}

function buildHoldMapFromCheckoutItems(items) {
  const holds = {};
  for (const item of items) {
    const productId = String(item?.productId || '').trim();
    if (!productId) {
      continue;
    }
    const quantityRaw = Number(item?.quantity);
    const quantity = Number.isFinite(quantityRaw)
      ? Math.max(1, Math.min(999, Math.floor(quantityRaw)))
      : 1;
    holds[productId] = (holds[productId] || 0) + quantity;
  }
  return holds;
}

async function assertCheckoutStockReady(db, FieldValue, HttpsError, uid, items) {
  const holdMap = buildHoldMapFromCheckoutItems(items);
  const productIds = Object.keys(holdMap);
  if (productIds.length === 0) {
    return { sessionRef: null, holdMap };
  }

  const sessionRef = db.collection(VAN2_CART_SESSION_COLLECTION).doc(uid);

  await db.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);
    const sessionHolds = sessionSnap.exists ? sessionSnap.data()?.holds || {} : {};

    for (const productId of productIds) {
      const requiredQty = holdMap[productId] || 0;
      const heldQty = Math.max(0, Math.floor(Number(sessionHolds[productId] || 0)));
      const productRef = db.collection('products').doc(productId);
      const productSnap = await transaction.get(productRef);

      if (!productSnap.exists) {
        throw new HttpsError('not-found', `ไม่พบสินค้า ${productId}`);
      }

      const trackedStock = readFiniteProductStock(productSnap.data()?.stock);
      if (trackedStock === null) {
        continue;
      }

      if (heldQty >= requiredQty) {
        continue;
      }

      const extraNeeded = requiredQty - heldQty;
      if (trackedStock < extraNeeded) {
        throw new HttpsError(
          'failed-precondition',
          `สต๊อกไม่พอสำหรับสินค้า ${productId}`,
        );
      }

      transaction.update(productRef, {
        stock: FieldValue.increment(-extraNeeded),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (sessionSnap.exists) {
      transaction.delete(sessionRef);
    }
  });

  return { sessionRef, holdMap };
}

let cachedOnlineRidersSnapshot = null;
let cachedOnlineRidersAtMs = 0;

async function getOnlineRidersSnapshot(db) {
  const now = Date.now();
  if (
    cachedOnlineRidersSnapshot &&
    now - cachedOnlineRidersAtMs < ONLINE_RIDERS_CACHE_TTL_MS
  ) {
    return cachedOnlineRidersSnapshot;
  }

  try {
    const poolDoc = await db.doc(RIDER_AVAILABILITY_DOC_PATH).get();
    const pool = poolDoc.data();
    const updatedAtMs = pool?.updatedAt?.toDate?.()?.getTime() || 0;
    if (pool && updatedAtMs > 0 && now - updatedAtMs <= RIDER_POOL_MAX_AGE_MS) {
      cachedOnlineRidersSnapshot = snapshotFromPool(pool);
      cachedOnlineRidersAtMs = now;
      return cachedOnlineRidersSnapshot;
    }
  } catch (_) {
    // Fall back to live riders query below.
  }

  cachedOnlineRidersSnapshot = await db
    .collection('riders')
    .where('onlineReady', '==', true)
    .get();
  cachedOnlineRidersAtMs = now;
  return cachedOnlineRidersSnapshot;
}

function parseDiscountPercent(value, parseNumber) {
  const parsed = parseNumber(value);
  if (parsed <= 0) {
    return 0;
  }
  if (parsed > 100) {
    return 100;
  }
  return parsed;
}

function applyMerchantDiscount(basePrice, discountPercent, parseNumber) {
  const pct = parseDiscountPercent(discountPercent, parseNumber);
  if (pct <= 0 || basePrice <= 0) {
    return basePrice;
  }
  return basePrice * (1 - pct / 100);
}

function resolveMerchantUnitPayout(product, parseNumber) {
  const listed = applyMerchantDiscount(
    parseNumber(product.price),
    product.discountPercent,
    parseNumber,
  );
  if (listed <= 0) {
    return 0;
  }
  return listed * (1 - MERCHANT_GP_RATE);
}

function merchantToppingPayout(rawPrice, parseNumber) {
  const value = parseNumber(rawPrice);
  if (value <= 0) {
    return 0;
  }
  return value * (1 - MERCHANT_GP_RATE);
}

function firstNonEmptyUrlFromList(raw) {
  if (!Array.isArray(raw)) {
    return '';
  }
  for (const entry of raw) {
    const url = String(entry ?? '').trim();
    if (url) {
      return url;
    }
  }
  return '';
}

function resolveProductImageUrl(product, item) {
  const originals = product?.imageUrls;
  const hasOriginals = Array.isArray(originals)
    && originals.some((entry) => String(entry ?? '').trim());

  let url = '';
  if (hasOriginals) {
    url = firstNonEmptyUrlFromList(originals);
  } else {
    url = firstNonEmptyUrlFromList(product?.thumbnailUrls);
  }
  if (!url) {
    for (const key of ['imageUrl', 'photoUrl', 'productImage', 'thumbnailUrl']) {
      url = String(product?.[key] ?? '').trim();
      if (url) {
        break;
      }
    }
  }
  if (!url) {
    url = String(item?.imageUrl ?? '').trim();
  }
  return url || null;
}

function resolveShopImageUrlFromRecord(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }
  for (const key of [
    'shopImageUrl',
    'storeImageUrl',
    'photoUrl',
    'imageUrl',
    'logoUrl',
    'profileImageUrl',
  ]) {
    const url = String(data[key] || '').trim();
    if (url) {
      return url;
    }
  }
  return null;
}

function resolveShopImageUrlFromProduct(product, item) {
  return resolveShopImageUrlFromRecord(product)
    || resolveShopImageUrlFromRecord(item)
    || null;
}

function isValidRiderCoordinates(lat, lng) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return false;
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return false;
  }
  if (lat === 0 && lng === 0) {
    return false;
  }
  return true;
}

function resolveShopCoordinatesFromRecord(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }
  const directLat = Number(data.shopLatitude ?? data.latitude ?? data.lat);
  const directLng = Number(
    data.shopLongitude ?? data.longitude ?? data.lng ?? data.lon ?? data.long,
  );
  if (isValidRiderCoordinates(directLat, directLng)) {
    return { latitude: directLat, longitude: directLng };
  }
  for (const locationKey of ['shopLocation', 'location', 'coordinates']) {
    const location = data[locationKey];
    if (!location || typeof location !== 'object') {
      continue;
    }
    const lat = Number(location.latitude ?? location.lat);
    const lng = Number(location.longitude ?? location.lng ?? location.lon ?? location.long);
    if (isValidRiderCoordinates(lat, lng)) {
      return { latitude: lat, longitude: lng };
    }
  }
  return null;
}

async function loadPublicShopProfileMap(db, shopIds) {
  const profileMap = new Map();
  const uniqueShopIds = [...new Set(
    (shopIds || []).map((shopId) => String(shopId || '').trim()).filter(Boolean),
  )];
  await Promise.all(uniqueShopIds.map(async (shopId) => {
    try {
      const snapshot = await db.collection('public_shops').doc(shopId).get();
      if (!snapshot.exists) {
        return;
      }
      const data = snapshot.data() || {};
      const shopImageUrl = resolveShopImageUrlFromRecord(data);
      const coords = resolveShopCoordinatesFromRecord(data);
      if (shopImageUrl || coords) {
        profileMap.set(shopId, {
          ...(shopImageUrl ? { shopImageUrl } : {}),
          ...(coords || {}),
        });
      }
    } catch (_) {
      // Optional enrichment — checkout must still succeed.
    }
  }));
  return profileMap;
}

function buildResolvedLineItem(item, product, helpers) {
  const {
    parseNumber,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    pricingRates,
  } = helpers;

  const quantityRaw = Number(item?.quantity);
  const quantity = Number.isFinite(quantityRaw)
    ? Math.max(1, Math.min(999, Math.floor(quantityRaw)))
    : 1;

  const taxable = isTaxableProduct(product);
  const basePrice = parseNumber(product.price);
  const adjustedBasePrice = applyProductMarkupWithRates(basePrice, taxable, pricingRates);
  const discountedBase = applyMerchantDiscount(
    basePrice,
    product.discountPercent,
    parseNumber,
  );
  const customerBase = applyProductMarkupWithRates(discountedBase, taxable, pricingRates);

  const toppingOptions = extractToppings(product, pricingRates);
  const toppingPriceByLabel = new Map(
    toppingOptions.map((option) => [
      canonicalizeToppingLabel(option.label),
      parseNumber(option.adjustedPrice),
    ]),
  );
  const toppingRawByLabel = new Map(
    toppingOptions.map((option) => [
      canonicalizeToppingLabel(option.label),
      parseNumber(option.rawPrice ?? option.price ?? option.adjustedPrice),
    ]),
  );

  const selectedToppings = Array.isArray(item?.selectedToppings) ? item.selectedToppings : [];
  let toppingTotal = 0;
  let toppingMerchantPayout = 0;
  for (const selected of selectedToppings) {
    const key = canonicalizeToppingLabel(selected);
    if (!key) {
      continue;
    }
    toppingTotal += toppingPriceByLabel.get(key) || 0;
    toppingMerchantPayout += merchantToppingPayout(
      toppingRawByLabel.get(key) || 0,
      parseNumber,
    );
  }

  const unitPrice = customerBase + toppingTotal;
  const merchantBasePrice = parseNumber(product.price);
  const merchantUnitPayout = resolveMerchantUnitPayout(product, parseNumber) + toppingMerchantPayout;
  const shopId = String(item?.shopId || product.ownerUid || '').trim();
  const shopName = String(product.shopName || item?.shopName || 'ร้านค้า').trim() || 'ร้านค้า';
  const imageUrl = resolveProductImageUrl(product, item);
  const shopImageUrl = resolveShopImageUrlFromProduct(product, item);

  return {
    productId: String(item?.productId || product.id || '').trim(),
    shopId: shopId || `shop-${String(item?.productId || '').trim()}`,
    shopName,
    shopImageUrl,
    shopLatitude: helpers.toFiniteOrNull(product.shopLatitude ?? item?.shopLatitude),
    shopLongitude: helpers.toFiniteOrNull(product.shopLongitude ?? item?.shopLongitude),
    productName: String(product.name || item?.productName || 'สินค้า').trim() || 'สินค้า',
    unitPrice,
    merchantBasePrice,
    discountPercent: parseDiscountPercent(product.discountPercent, parseNumber),
    merchantUnitPayout,
    imageUrl: imageUrl || null,
    selectedToppings,
    quantity,
    preparationTimeMinutes: Math.max(
      1,
      parseNumber(product.preparationTimeMinutes ?? item?.preparationTimeMinutes) || 10,
    ),
    parcelWeightGrams: Math.max(
      1,
      parseNumber(item?.parcelWeightGrams ?? product.parcelWeightGrams) || 1000,
    ),
    parcelLengthCm: helpers.toFiniteOrNull(item?.parcelLengthCm ?? product.parcelLengthCm),
    parcelWidthCm: helpers.toFiniteOrNull(item?.parcelWidthCm ?? product.parcelWidthCm),
    parcelHeightCm: helpers.toFiniteOrNull(item?.parcelHeightCm ?? product.parcelHeightCm),
  };
}

async function computeVan2CartTotals({
  uid,
  items,
  customerLatitude,
  customerLongitude,
  couponCode,
  helpers,
}) {
  const {
    parseNumber,
    loadProductsByIds,
    getPricingRates,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    haversineDistanceKm,
    computeShippingFeeByDistance,
    computeMarketCheckoutFees,
    applyCartDiscounts,
    toFiniteOrNull,
  } = helpers;

  const productIds = [
    ...new Set(items.map((item) => String(item?.productId || '').trim()).filter(Boolean)),
  ];
  if (productIds.length === 0) {
    throw new helpers.HttpsError('invalid-argument', 'ไม่พบสินค้าในคำขอ');
  }

  const products = await loadProductsByIds(productIds);
  const pricingRates = await getPricingRates();

  let subtotal = 0;
  let itemCount = 0;
  const shops = new Map();
  const resolvedLines = [];

  for (const item of items) {
    const productId = String(item?.productId || '').trim();
    const product = products.get(productId);
    if (!product) {
      throw new helpers.HttpsError('not-found', `ไม่พบข้อมูลสินค้า ${productId}`);
    }

    const line = buildResolvedLineItem(item, { ...product, id: productId }, {
      parseNumber,
      isTaxableProduct,
      applyProductMarkupWithRates,
      extractToppings,
      canonicalizeToppingLabel,
      pricingRates,
      toFiniteOrNull,
    });
    itemCount += line.quantity;
    subtotal += line.unitPrice * line.quantity;
    resolvedLines.push(line);

    if (!shops.has(line.shopId)) {
      shops.set(line.shopId, {
        shopName: line.shopName,
        latitude: line.shopLatitude,
        longitude: line.shopLongitude,
      });
    }
  }

  let shippingFee = 0;
  for (const shop of shops.values()) {
    if (
      shop.latitude == null
      || shop.longitude == null
      || !isValidRiderCoordinates(shop.latitude, shop.longitude)
    ) {
      shippingFee += pricingRates.shippingMissingCoordsFee ?? 25;
      continue;
    }
    const distanceKm = haversineDistanceKm(
      shop.latitude,
      shop.longitude,
      customerLatitude,
      customerLongitude,
    );
    shippingFee += computeShippingFeeByDistance(distanceKm, pricingRates);
  }

  const marketFees = computeMarketCheckoutFees(shops, pricingRates);
  const discounts = await applyCartDiscounts({
    userId: uid,
    subtotal,
    shippingFee,
    marketTotalFees: marketFees.marketTotalFees,
    couponCode: couponCode || null,
    context: {
      subtotal,
      itemCount,
      shopIds: [...shops.keys()],
      productIds,
      customerLatitude,
      customerLongitude,
    },
    rates: pricingRates,
  });

  return {
    subtotal,
    shippingFee,
    marketFees,
    discounts,
    grandTotal: discounts.grandTotal,
    itemCount,
    shopCount: shops.size,
    pricingRates,
    resolvedLines,
  };
}

async function persistCheckoutQuote(db, FieldValue, uid, totals, items) {
  const quoteRef = db.collection(CHECKOUT_QUOTES_COLLECTION).doc();
  const expiresAt = Date.now() + CHECKOUT_QUOTE_TTL_MS;
  await quoteRef.set({
    customerId: uid,
    grandTotal: totals.grandTotal,
    subtotal: totals.subtotal,
    shippingFee: totals.shippingFee,
    discountTotal: totals.discounts.discountTotal,
    itemCount: totals.itemCount,
    shopCount: totals.shopCount,
    itemsFingerprint: JSON.stringify(
      items.map((item) => ({
        productId: String(item?.productId || '').trim(),
        quantity: Number(item?.quantity) || 1,
        shopId: String(item?.shopId || '').trim(),
        selectedToppings: Array.isArray(item?.selectedToppings) ? item.selectedToppings : [],
      })),
    ),
    consumed: false,
    expiresAt,
    createdAt: FieldValue.serverTimestamp(),
  });
  return quoteRef.id;
}

async function validateCheckoutQuote(db, quoteId, uid, expectedGrandTotal, parseNumber, itemsFingerprint) {
  const quoteRef = db.collection(CHECKOUT_QUOTES_COLLECTION).doc(String(quoteId || '').trim());
  const snapshot = await quoteRef.get();
  if (!snapshot.exists) {
    throw new Error('ไม่พบ checkout quote');
  }
  const data = snapshot.data() || {};
  if (data.customerId !== uid) {
    throw new Error('checkout quote ไม่ตรงกับผู้ใช้');
  }
  if (data.consumed === true) {
    throw new Error('checkout quote ถูกใช้แล้ว');
  }
  const expiresAt = Number(data.expiresAt || 0);
  if (expiresAt > 0 && expiresAt < Date.now()) {
    throw new Error('checkout quote หมดอายุ');
  }
  const quotedGrandTotal = parseNumber(data.grandTotal);
  const expected = parseNumber(expectedGrandTotal);
  if (Math.abs(quotedGrandTotal - expected) > 0.02) {
    throw new Error('ยอดรวมไม่ตรงกับ quote');
  }
  if (itemsFingerprint && String(data.itemsFingerprint || '') !== String(itemsFingerprint)) {
    throw new Error('รายการในตะกร้าไม่ตรงกับ quote');
  }
  return quoteRef;
}

async function atomicallyConsumeCheckoutReservation(
  db,
  FieldValue,
  HttpsError,
  {
    checkoutQuoteId,
    uid,
    expectedGrandTotal,
    itemsFingerprint,
    paymentSessionId,
    isOmiseVerifiedPayment,
    paymentMethod,
    parseNumber,
  },
) {
  const quoteRef = db.collection(CHECKOUT_QUOTES_COLLECTION).doc(String(checkoutQuoteId || '').trim());
  const sessionRef =
    isOmiseVerifiedPayment && paymentSessionId
      ? db.collection('payment_sessions').doc(String(paymentSessionId).trim())
      : null;

  await db.runTransaction(async (transaction) => {
    const quoteSnap = await transaction.get(quoteRef);
    if (!quoteSnap.exists) {
      throw new HttpsError('failed-precondition', 'ไม่พบ checkout quote');
    }
    const quoteData = quoteSnap.data() || {};
    if (quoteData.customerId !== uid) {
      throw new HttpsError('permission-denied', 'checkout quote ไม่ตรงกับผู้ใช้');
    }
    if (quoteData.consumed === true) {
      throw new HttpsError('failed-precondition', 'checkout quote ถูกใช้แล้ว');
    }
    const expiresAt = Number(quoteData.expiresAt || 0);
    if (expiresAt > 0 && expiresAt < Date.now()) {
      throw new HttpsError('failed-precondition', 'checkout quote หมดอายุ');
    }
    const quotedGrandTotal = parseNumber(quoteData.grandTotal);
    const expected = parseNumber(expectedGrandTotal);
    if (Math.abs(quotedGrandTotal - expected) > 0.02) {
      throw new HttpsError('failed-precondition', 'ยอดรวมไม่ตรงกับ quote');
    }
    if (
      itemsFingerprint
      && String(quoteData.itemsFingerprint || '') !== String(itemsFingerprint)
    ) {
      throw new HttpsError('failed-precondition', 'รายการในตะกร้าไม่ตรงกับ quote');
    }

    if (sessionRef) {
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
      if (Math.abs(sessionAmount - expected) > 0.01) {
        throw new HttpsError('failed-precondition', 'ยอดชำระ Omise ไม่ตรงกับตะกร้า');
      }
      if (String(session.checkoutQuoteId || '') !== checkoutQuoteId) {
        throw new HttpsError('failed-precondition', 'checkout quote ไม่ตรงกับ payment session');
      }
    }

    transaction.set(
      quoteRef,
      {
        consumed: true,
        consumedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (sessionRef) {
      transaction.set(
        sessionRef,
        {
          consumed: true,
          consumedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  });

  return { quoteRef, sessionRef };
}

function groupLinesByShop(resolvedLines) {
  const grouped = new Map();
  for (const line of resolvedLines) {
    if (!grouped.has(line.shopId)) {
      grouped.set(line.shopId, []);
    }
    grouped.get(line.shopId).push(line);
  }
  return grouped;
}

function buildOrderCode(prefix, orderId, now = new Date()) {
  const y = String(now.getFullYear()).padStart(4, '0');
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const suffix = String(orderId).substring(0, 6).toUpperCase();
  return `${prefix}-${y}${m}${d}-${suffix}`;
}

function haversineMeters(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadiusM = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusM * c;
}

async function findNearestRiderForShop(db, shopLatitude, shopLongitude) {
  const excludedBreakdown = {};
  const addExcluded = (reason) => {
    excludedBreakdown[reason] = (excludedBreakdown[reason] || 0) + 1;
  };

  if (!Number.isFinite(shopLatitude) || !Number.isFinite(shopLongitude)) {
    try {
      const snapshot = await getOnlineRidersSnapshot(db);
      if (snapshot.size === 1) {
        const riderId = snapshot.docs[0].id;
        return {
          rider: { riderId, distanceKm: 0 },
          searchedRadiusKm: 0,
          onlineRiderCount: 1,
          eligibleRiderCount: 1,
          excludedRiderCount: 0,
          excludedBreakdown,
          reason: 'single_online_no_shop_coords_fallback',
        };
      }
      if (snapshot.size > 1) {
        let freshest = null;
        let freshestAgeMs = Number.POSITIVE_INFINITY;
        for (const doc of snapshot.docs) {
          const data = doc.data() || {};
          const updatedAt = data.locationUpdatedAt?.toDate?.() || data.updatedAt?.toDate?.() || null;
          if (!updatedAt) {
            addExcluded('missing_location_timestamp');
            continue;
          }
          const ageMs = Date.now() - updatedAt.getTime();
          if (ageMs < freshestAgeMs) {
            freshestAgeMs = ageMs;
            freshest = doc.id;
          }
        }
        if (freshest) {
          return {
            rider: { riderId: freshest, distanceKm: 0 },
            searchedRadiusKm: 0,
            onlineRiderCount: snapshot.size,
            eligibleRiderCount: 1,
            excludedRiderCount: snapshot.size - 1,
            excludedBreakdown,
            reason: 'multi_online_no_shop_coords_fallback',
          };
        }
      }
      return {
        rider: null,
        searchedRadiusKm: 0,
        onlineRiderCount: snapshot.size,
        eligibleRiderCount: 0,
        excludedRiderCount: snapshot.size,
        excludedBreakdown,
        reason: 'missing_shop_coordinates',
      };
    } catch (error) {
      return {
        rider: null,
        searchedRadiusKm: 0,
        onlineRiderCount: 0,
        eligibleRiderCount: 0,
        excludedRiderCount: 0,
        excludedBreakdown,
        reason: `rider_query_failed:${error}`,
      };
    }
  }

  const snapshot = await getOnlineRidersSnapshot(db);
  const candidates = [];
  const fallbackCandidates = [];
  const singleOnlineRiderId = snapshot.size === 1 ? snapshot.docs[0].id : null;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const geo = data.currentLocation;
    const lat = geo?.latitude ?? Number(data.latitude);
    const lng = geo?.longitude ?? Number(data.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      addExcluded('missing_coordinates');
      continue;
    }
    if (!isValidRiderCoordinates(lat, lng)) {
      addExcluded('invalid_coordinates');
      continue;
    }
    const meters = haversineMeters(shopLatitude, shopLongitude, lat, lng);
    const riderDistance = { riderId: doc.id, distanceKm: meters / 1000 };
    fallbackCandidates.push(riderDistance);

    const locationStatus = String(data.locationStatus || '').trim();
    const locationUpdatedAt = data.locationUpdatedAt?.toDate?.() || data.updatedAt?.toDate?.() || null;
    if (locationStatus === 'offline') {
      addExcluded('offline');
      continue;
    }
    if (!locationUpdatedAt) {
      addExcluded('missing_location_timestamp');
      continue;
    }
    const ageMinutes = (Date.now() - locationUpdatedAt.getTime()) / 60000;
    if (ageMinutes > RIDER_FRESH_LOCATION_MINUTES) {
      addExcluded('stale_location');
      continue;
    }
    candidates.push(riderDistance);
  }

  if (candidates.length === 0) {
    if (fallbackCandidates.length === 1) {
      return {
        rider: fallbackCandidates[0],
        searchedRadiusKm: 10,
        onlineRiderCount: snapshot.size,
        eligibleRiderCount: 1,
        excludedRiderCount: Math.max(0, snapshot.size - 1),
        excludedBreakdown,
        reason: 'single_online_fallback',
      };
    }
    if (fallbackCandidates.length > 1) {
      const nearest = [...fallbackCandidates].sort((a, b) => a.distanceKm - b.distanceKm);
      return {
        rider: nearest[0],
        searchedRadiusKm: 10,
        onlineRiderCount: snapshot.size,
        eligibleRiderCount: 1,
        excludedRiderCount: snapshot.size - fallbackCandidates.length,
        excludedBreakdown,
        reason: 'multi_online_stale_location_fallback',
      };
    }
    if (singleOnlineRiderId) {
      return {
        rider: { riderId: singleOnlineRiderId, distanceKm: 0 },
        searchedRadiusKm: 10,
        onlineRiderCount: snapshot.size,
        eligibleRiderCount: 1,
        excludedRiderCount: 0,
        excludedBreakdown,
        reason: 'single_online_no_location_fallback',
      };
    }
    return {
      rider: null,
      searchedRadiusKm: 10,
      onlineRiderCount: snapshot.size,
      eligibleRiderCount: 0,
      excludedRiderCount: snapshot.size,
      excludedBreakdown,
      reason: snapshot.size === 0 ? 'no_online_riders' : 'no_eligible_online_riders',
    };
  }

  for (let radiusKm = 2; radiusKm <= 10; radiusKm += 2) {
    const inRadius = candidates
      .filter((candidate) => candidate.distanceKm <= radiusKm)
      .sort((a, b) => a.distanceKm - b.distanceKm);
    if (inRadius.length > 0) {
      return {
        rider: inRadius[0],
        searchedRadiusKm: radiusKm,
        onlineRiderCount: snapshot.size,
        eligibleRiderCount: candidates.length,
        excludedRiderCount: snapshot.size - candidates.length,
        excludedBreakdown,
      };
    }
  }

  const nearest = [...candidates].sort((a, b) => a.distanceKm - b.distanceKm);
  return {
    rider: nearest[0],
    searchedRadiusKm: 10,
    onlineRiderCount: snapshot.size,
    eligibleRiderCount: candidates.length,
    excludedRiderCount: snapshot.size - candidates.length,
    excludedBreakdown,
    reason: 'nearest_out_of_radius_fallback',
  };
}

function summarizeNationwideParcel(lines) {
  const totalQuantity = lines.reduce((sum, line) => sum + line.quantity, 0);
  let totalWeightGrams = lines.reduce(
    (sum, line) => sum + line.parcelWeightGrams * line.quantity,
    0,
  );
  if (totalWeightGrams <= 0) {
    totalWeightGrams = totalQuantity * 1000;
  }
  const maxDim = (readValue) => {
    let maxValue = null;
    for (const line of lines) {
      const value = readValue(line);
      if (value == null || value <= 0) {
        continue;
      }
      if (maxValue == null || value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue;
  };
  return {
    totalWeightGrams,
    totalQuantity,
    lengthCm: maxDim((line) => line.parcelLengthCm) ?? 20,
    widthCm: maxDim((line) => line.parcelWidthCm) ?? 15,
    heightCm: maxDim((line) => line.parcelHeightCm) ?? 10,
  };
}

function computeNationwideFee(weightGrams, postalCode, pricingRates, parseNumber) {
  const baseFee = parseNumber(pricingRates.nationwideBaseFee) || DEFAULT_NATIONWIDE_BASE_FEE;
  const perKgFee = parseNumber(pricingRates.nationwidePerKgFee) || DEFAULT_NATIONWIDE_PER_KG_FEE;
  const remoteSurcharge =
    parseNumber(pricingRates.nationwideRemoteSurcharge) || DEFAULT_NATIONWIDE_REMOTE_SURCHARGE;
  const weightKg = Math.max(1, Math.ceil(Math.max(0, weightGrams) / 1000));
  let fee = baseFee + perKgFee * weightKg;
  const normalizedPostal = String(postalCode || '').trim();
  if (
    normalizedPostal.startsWith('58') ||
    normalizedPostal.startsWith('95') ||
    normalizedPostal.startsWith('96')
  ) {
    fee += remoteSurcharge;
  }
  return fee;
}

function buildProductsPayload(lines) {
  return lines.map((line) => {
    const imageUrl = String(line.imageUrl || '').trim();
    const merchantLinePayout = line.merchantUnitPayout * line.quantity;
    return {
      productId: line.productId,
      name: line.productName,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      merchantBasePrice: line.merchantBasePrice,
      discountPercent: line.discountPercent,
      merchantUnitPayout: line.merchantUnitPayout,
      merchantLinePayout,
      preparationTimeMinutes: line.preparationTimeMinutes,
      preparingDuration: line.preparationTimeMinutes * 60 * 1000,
      selectedToppings: line.selectedToppings,
      lineTotal: line.unitPrice * line.quantity,
      ...(imageUrl ? { imageUrl, productImage: imageUrl } : {}),
      ...(line.shopImageUrl ? { shopImageUrl: line.shopImageUrl } : {}),
      ...(line.parcelWeightGrams ? { parcelWeightGrams: line.parcelWeightGrams } : {}),
      ...(line.parcelLengthCm != null ? { parcelLengthCm: line.parcelLengthCm } : {}),
      ...(line.parcelWidthCm != null ? { parcelWidthCm: line.parcelWidthCm } : {}),
      ...(line.parcelHeightCm != null ? { parcelHeightCm: line.parcelHeightCm } : {}),
    };
  });
}

async function createCheckoutOrdersHandler(request, deps) {
  const {
    db,
    admin,
    FieldValue,
    HttpsError,
    parseNumber,
    loadProductsByIds,
    getPricingRates,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    haversineDistanceKm,
    computeShippingFeeByDistance,
    computeMarketCheckoutFees,
    applyCartDiscounts,
    normalizeCouponCode,
    toFiniteOrNull,
    isShopNearMarketHub,
  } = deps;

  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนสร้างออเดอร์');
  }

  const { assertNonAnonymous } = require('./travel_orders');
  assertNonAnonymous(request, HttpsError);

  const uid = request.auth.uid;
  const items = Array.isArray(request.data?.items) ? request.data.items : [];
  if (items.length === 0) {
    throw new HttpsError('invalid-argument', 'ไม่มีสินค้าในตะกร้า');
  }
  if (items.length > 200) {
    throw new HttpsError('invalid-argument', 'จำนวนสินค้าในตะกร้ามากเกินไป');
  }

  const customerLatitude = parseNumber(request.data?.customerLatitude);
  const customerLongitude = parseNumber(request.data?.customerLongitude);
  if (!Number.isFinite(customerLatitude) || !Number.isFinite(customerLongitude)) {
    throw new HttpsError('invalid-argument', 'พิกัดลูกค้าไม่ถูกต้อง');
  }

  const paymentMethod = String(request.data?.paymentMethod || '').trim();
  const paymentStatus = String(request.data?.paymentStatus || '').trim();
  const verificationFeedbackId = String(request.data?.verificationFeedbackId || '').trim();
  const paymentGroupId = String(request.data?.paymentGroupId || '').trim();
  const paymentSessionId = String(request.data?.paymentSessionId || '').trim();
  const OMISE_PAYMENT_METHODS = new Set([
    'omise_promptpay',
    'omise_card',
    'omise_mobile_banking',
    'omise_truemoney',
  ]);
  const allowedPaymentStatuses = ['cash_on_delivery', 'awaiting_slip_review', 'verified'];
  if (!allowedPaymentStatuses.includes(paymentStatus)) {
    throw new HttpsError('invalid-argument', 'สถานะชำระเงินไม่รองรับ');
  }
  if (paymentStatus === 'verified' && paymentMethod === 'promptpay_qr') {
    throw new HttpsError(
      'failed-precondition',
      'ระบบสแกนจ่าย+สลิp ถูกยกเลิกแล้ว กรุณาใช้ Omise',
    );
  }
  let omisePaymentSession = null;
  if (paymentStatus === 'verified') {
    if (OMISE_PAYMENT_METHODS.has(paymentMethod)) {
      if (!paymentSessionId) {
        throw new HttpsError('invalid-argument', 'ต้องมี paymentSessionId');
      }
      const sessionDoc = await db.collection('payment_sessions').doc(paymentSessionId).get();
      if (!sessionDoc.exists) {
        throw new HttpsError('failed-precondition', 'ไม่พบ payment session');
      }
      omisePaymentSession = sessionDoc.data() || {};
      if (String(omisePaymentSession.uid || '') !== uid) {
        throw new HttpsError('permission-denied', 'payment session ไม่ตรงกับผู้ใช้');
      }
      if (omisePaymentSession.status !== 'paid') {
        throw new HttpsError('failed-precondition', 'การชำระเงินยังไม่สำเร็จ');
      }
      if (String(omisePaymentSession.channel || '') !== paymentMethod) {
        throw new HttpsError('failed-precondition', 'ช่องทางชำระเงินไม่ตรงกับ session');
      }
    } else if (!verificationFeedbackId || !paymentGroupId) {
      throw new HttpsError('invalid-argument', 'ข้อมูลการชำระเงินไม่ครบ');
    } else if (paymentMethod !== 'promptpay_qr') {
      throw new HttpsError('invalid-argument', 'การชำระเงินที่ยืนยันแล้วไม่รองรับช่องทางนี้');
    }
  }
  const isVerifiedPayment = paymentStatus === 'verified';
  const isOmiseVerifiedPayment =
    isVerifiedPayment && OMISE_PAYMENT_METHODS.has(paymentMethod);
  const resolvedPaymentGroupId = isOmiseVerifiedPayment
    ? paymentSessionId
    : paymentGroupId;
  const resolvedVerificationFeedbackId = isOmiseVerifiedPayment
    ? paymentSessionId
    : verificationFeedbackId;

  const helpers = {
    parseNumber,
    loadProductsByIds,
    getPricingRates,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    haversineDistanceKm,
    computeShippingFeeByDistance,
    computeMarketCheckoutFees,
    applyCartDiscounts,
    toFiniteOrNull,
    HttpsError,
  };

  const totals = await computeVan2CartTotals({
    uid,
    items,
    customerLatitude,
    customerLongitude,
    couponCode: normalizeCouponCode(request.data?.couponCode),
    helpers,
  });

  const checkoutQuoteId = String(request.data?.checkoutQuoteId || '').trim();
  if (!checkoutQuoteId) {
    throw new HttpsError('failed-precondition', 'ต้องมี checkout quote ก่อนสร้างออเดอร์');
  }
  const itemsFingerprint = JSON.stringify(
    items.map((item) => ({
      productId: String(item?.productId || '').trim(),
      quantity: Number(item?.quantity) || 1,
      shopId: String(item?.shopId || '').trim(),
      selectedToppings: Array.isArray(item?.selectedToppings) ? item.selectedToppings : [],
    })),
  );

  let quoteRef = null;
  try {
    const reservation = await atomicallyConsumeCheckoutReservation(
      db,
      FieldValue,
      HttpsError,
      {
        checkoutQuoteId,
        uid,
        expectedGrandTotal: totals.grandTotal,
        itemsFingerprint,
        paymentSessionId,
        isOmiseVerifiedPayment,
        paymentMethod,
        parseNumber,
      },
    );
    quoteRef = reservation.quoteRef;
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('failed-precondition', String(error.message || error));
  }

  if (isOmiseVerifiedPayment) {
    const sessionAmount = parseNumber(omisePaymentSession?.amount);
    if (Math.abs(sessionAmount - totals.grandTotal) > 0.01) {
      throw new HttpsError('failed-precondition', 'ยอดชำระ Omise ไม่ตรงกับตะกร้า');
    }
    if (String(omisePaymentSession?.checkoutQuoteId || '') !== checkoutQuoteId) {
      throw new HttpsError('failed-precondition', 'checkout quote ไม่ตรงกับ payment session');
    }
  }

  const userRecord = await admin.auth().getUser(uid);
  const customerLocation = request.data?.customerLocation || {};
  const locationLabel = String(customerLocation.label || '').trim() || 'ตำแหน่งลูกค้า';
  const notifyRider = request.data?.notifyRider === true;
  const riderNotifyReady = request.data?.riderNotifyReady === true;
  const paymentMethodLabel = String(request.data?.paymentMethodLabel || paymentMethod).trim();
  const paymentStatusLabel = String(request.data?.paymentStatusLabel || paymentStatus).trim();
  const auditSource = String(request.data?.auditSource || 'cloud_function_checkout').trim();
  const createdEventLabel = String(request.data?.createdEventLabel || 'ลูกค้าสร้างออเดอร์').trim();

  const grouped = groupLinesByShop(totals.resolvedLines);
  const publicShopProfileMap = await loadPublicShopProfileMap(db, [...grouped.keys()]);
  const shopSubtotals = {};
  let combinedSubtotal = 0;
  for (const [shopId, lines] of grouped.entries()) {
    const subtotal = lines.reduce((sum, line) => sum + line.unitPrice * line.quantity, 0);
    shopSubtotals[shopId] = subtotal;
    combinedSubtotal += subtotal;
  }

  await assertCheckoutStockReady(db, FieldValue, HttpsError, uid, items);

  const createdOrderIds = [];
  const shopsWithoutRider = [];
  let combinedGrandTotal = 0;
  let marketCollectionAssigned = false;
  const batch = db.batch();
  const now = new Date();
  const paymentExpiresAt =
    paymentMethod === 'promptpay_qr' && paymentStatus === 'awaiting_slip_review'
      ? admin.firestore.Timestamp.fromDate(new Date(now.getTime() + 30 * 60 * 1000))
      : null;
  const omiseChargeId = isOmiseVerifiedPayment
    ? String(omisePaymentSession?.omiseChargeId || '').trim() || null
    : null;

  for (const [shopId, lines] of grouped.entries()) {
    const firstItem = lines[0];
    const subtotal = shopSubtotals[shopId] || 0;
    const merchantSubtotal = lines.reduce(
      (sum, line) => sum + line.merchantUnitPayout * line.quantity,
      0,
    );
    const totalQuantity = lines.reduce((sum, line) => sum + line.quantity, 0);
    const preparationTimeMinutes = lines.reduce(
      (max, line) => Math.max(max, line.preparationTimeMinutes),
      10,
    );
    const preparingDuration = preparationTimeMinutes * 60 * 1000;

    let shippingFee = totals.pricingRates.shippingMissingCoordsFee ?? 25;
    if (
      firstItem.shopLatitude != null
      && firstItem.shopLongitude != null
      && isValidRiderCoordinates(firstItem.shopLatitude, firstItem.shopLongitude)
    ) {
      const distanceKm = haversineDistanceKm(
        firstItem.shopLatitude,
        firstItem.shopLongitude,
        customerLatitude,
        customerLongitude,
      );
      shippingFee = computeShippingFeeByDistance(distanceKm, totals.pricingRates);
    }

    const shopQualifiesForMarket = isShopNearMarketHub(
      firstItem.shopLatitude,
      firstItem.shopLongitude,
      totals.pricingRates,
    );
    const orderServiceFee = shopQualifiesForMarket
      ? totals.pricingRates.marketServiceFeePerOrder ?? 5
      : 0;
    let orderCollectionFee = 0;
    if (!marketCollectionAssigned && shopQualifiesForMarket && totals.marketFees.applies) {
      orderCollectionFee = totals.pricingRates.marketMultiShopCollectionFee ?? 5;
      marketCollectionAssigned = orderCollectionFee > 0;
    }

    const discountShare =
      combinedSubtotal > 0
        ? totals.discounts.discountTotal * (subtotal / combinedSubtotal)
        : 0;
    const promotionShare =
      combinedSubtotal > 0
        ? totals.discounts.promotionDiscount * (subtotal / combinedSubtotal)
        : 0;
    const couponShare =
      combinedSubtotal > 0
        ? totals.discounts.couponDiscount * (subtotal / combinedSubtotal)
        : 0;
    const grandTotal = Math.max(
      0,
      subtotal + shippingFee + orderServiceFee + orderCollectionFee - discountShare,
    );
    combinedGrandTotal += grandTotal;

    const riderSearch = await findNearestRiderForShop(
      db,
      firstItem.shopLatitude,
      firstItem.shopLongitude,
    );
    const assignedRider = riderSearch.rider;
    if (!assignedRider) {
      shopsWithoutRider.push(`${firstItem.shopName} (${riderSearch.reason || 'no_rider'})`);
    }

    const shouldAssignRiderImmediately = notifyRider && assignedRider != null;
    const initialOrderStatus = isVerifiedPayment
      ? (assignedRider == null ? 'awaiting_rider' : 'pending')
      : assignedRider == null
        ? notifyRider
          ? 'awaiting_rider'
          : 'awaiting_payment_slip_review'
        : notifyRider
          ? 'pending'
          : 'awaiting_payment_slip_review';
    const initialStatusLabel = isVerifiedPayment
      ? (assignedRider == null ? 'awaiting_nearest_rider' : 'pending_customer_confirmation')
      : assignedRider == null
        ? notifyRider
          ? 'awaiting_nearest_rider'
          : 'awaiting_payment_slip_review'
        : notifyRider
          ? 'pending_customer_confirmation'
          : 'awaiting_payment_slip_review';

    const orderRef = db.collection('orders').doc();
    const orderCode = buildOrderCode('ORD', orderRef.id, now);
    const products = buildProductsPayload(lines);
    const productIds = [...new Set(lines.map((line) => line.productId).filter(Boolean))];
    const publicShopProfile = publicShopProfileMap.get(shopId) || {};
    const shopImageUrl =
      String(firstItem.shopImageUrl || '').trim()
      || String(publicShopProfile.shopImageUrl || '').trim()
      || null;
    const shopLatitude = isValidRiderCoordinates(firstItem.shopLatitude, firstItem.shopLongitude)
      ? firstItem.shopLatitude
      : isValidRiderCoordinates(publicShopProfile.latitude, publicShopProfile.longitude)
        ? publicShopProfile.latitude
        : null;
    const shopLongitude = isValidRiderCoordinates(firstItem.shopLatitude, firstItem.shopLongitude)
      ? firstItem.shopLongitude
      : isValidRiderCoordinates(publicShopProfile.latitude, publicShopProfile.longitude)
        ? publicShopProfile.longitude
        : null;
    const hasShopCoordinates = isValidRiderCoordinates(shopLatitude, shopLongitude);

    const orderPayload = {
      orderId: orderRef.id,
      orderCode,
      status: initialOrderStatus,
      statusLabel: initialStatusLabel,
      customerConfirmed: true,
      customerConfirmedAt: FieldValue.serverTimestamp(),
      riderNotifyReady,
      paymentMethod,
      paymentMethodLabel,
      paymentStatus,
      paymentStatusLabel,
      ...(paymentExpiresAt
        ? {
            paymentExpiresAt,
            paymentExpiresInMinutes: 30,
            stockHoldStatus: 'pending',
          }
        : {}),
      sourceApp: 'van2_customer',
      customerId: uid,
      customerEmail: userRecord.email || null,
      customerPhone: userRecord.phoneNumber || null,
      customerSnapshot: {
        uid,
        email: userRecord.email || null,
        phoneNumber: userRecord.phoneNumber || null,
      },
      shopOwnerId: shopId,
      shopId,
      shopName: firstItem.shopName,
      ...(shopImageUrl || hasShopCoordinates
        ? {
            shopSnapshot: {
              shopName: firstItem.shopName,
              ownerId: shopId,
              ...(shopImageUrl ? { shopImageUrl } : {}),
              ...(hasShopCoordinates
                ? {
                    shopLatitude,
                    shopLongitude,
                    shopLocation: {
                      latitude: shopLatitude,
                      longitude: shopLongitude,
                    },
                  }
                : {}),
            },
          }
        : {}),
      ...(shopImageUrl ? { shopImageUrl } : {}),
      ...(hasShopCoordinates
        ? {
            shopLatitude,
            shopLongitude,
            shopLocation: {
              latitude: shopLatitude,
              longitude: shopLongitude,
            },
          }
        : {}),
      driverId: shouldAssignRiderImmediately ? assignedRider.riderId : null,
      driverName: null,
      driverPhone: null,
      assignedRiderAt:
        shouldAssignRiderImmediately ? FieldValue.serverTimestamp() : null,
      customerLocation: {
        latitude: customerLatitude,
        longitude: customerLongitude,
        label: locationLabel,
      },
      deliverySnapshot: {
        latitude: customerLatitude,
        longitude: customerLongitude,
        locationLabel,
      },
      itemCount: lines.length,
      totalQuantity,
      preparationTimeMinutes,
      preparingDuration,
      products,
      productIds,
      totalPrice: subtotal,
      subtotal,
      merchantSubtotal,
      shippingFee,
      serviceFee: orderServiceFee,
      multiShopCollectionFee: orderCollectionFee,
      ...(totals.marketFees.applies && shopQualifiesForMarket
        ? {
            marketHubFeesApplied: true,
            marketQualifyingShopCount: totals.marketFees.qualifyingShopCount,
          }
        : {}),
      grandTotal,
      ...(discountShare > 0
        ? {
            promotionDiscount: promotionShare,
            couponDiscount: couponShare,
            discountTotal: discountShare,
            ...(normalizeCouponCode(request.data?.couponCode)
              ? { appliedCouponCode: normalizeCouponCode(request.data?.couponCode) }
              : {}),
            discountLines: totals.discounts.discountLines,
          }
        : {}),
      riderSearch: {
        stepKm: 2,
        maxRadiusKm: 10,
        searchedRadiusKm: riderSearch.searchedRadiusKm,
        onlineRiderCount: riderSearch.onlineRiderCount,
        eligibleRiderCount: riderSearch.eligibleRiderCount,
        matched: assignedRider != null,
        matchedRiderId: assignedRider?.riderId ?? null,
        matchedDistanceKm: assignedRider?.distanceKm ?? null,
        ...(riderSearch.excludedRiderCount > 0
          ? { excludedRiderCount: riderSearch.excludedRiderCount }
          : {}),
        ...(Object.keys(riderSearch.excludedBreakdown || {}).length > 0
          ? { excludedBreakdown: riderSearch.excludedBreakdown }
          : {}),
        ...(riderSearch.reason ? { reason: riderSearch.reason } : {}),
      },
      checkoutQuoteId: checkoutQuoteId || null,
      ...(isVerifiedPayment
        ? {
            paymentGroupId: resolvedPaymentGroupId,
            paymentSubmittedAt: FieldValue.serverTimestamp(),
            ...(isOmiseVerifiedPayment
              ? {
                  paymentSessionId,
                  paymentVerification: {
                    provider: 'omise',
                    providerLabel: 'Omise',
                    feedbackId: resolvedVerificationFeedbackId,
                    paymentGroupId: resolvedPaymentGroupId,
                    paymentSessionId,
                    omiseChargeId,
                    expectedCombinedAmount: totals.grandTotal,
                    verifiedAmount: parseNumber(omisePaymentSession?.amount),
                    status: 'verified',
                    statusLabel: 'ชำระเงินผ่าน Omise แล้ว',
                    message: 'Omise charge successful',
                    checkedAt: FieldValue.serverTimestamp(),
                  },
                  settlement: {
                    shopPayout: {
                      amount: merchantSubtotal,
                      status: 'pending',
                      fundingSource: 'platform_float',
                      paymentProvider: 'omise',
                      omiseChargeId,
                      paymentSessionId,
                      omiseExpectedSettleAt: admin.firestore.Timestamp.fromDate(
                        new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000),
                      ),
                    },
                  },
                }
              : {
                  paymentSlip: {
                    storagePath: String(request.data?.slipStoragePath || '').trim(),
                    downloadUrl: String(request.data?.slipDownloadUrl || '').trim(),
                    fileName: String(request.data?.slipFileName || 'slip.jpg').trim(),
                    contentType: request.data?.slipContentType || null,
                    sizeBytes: parseNumber(request.data?.slipSizeBytes),
                    uploadedBy: uid,
                    uploadedAt: FieldValue.serverTimestamp(),
                  },
                  paymentVerification: {
                    provider: 'slipok',
                    providerLabel: 'Slip OK',
                    feedbackId: verificationFeedbackId,
                    paymentGroupId,
                    expectedCombinedAmount: combinedGrandTotal,
                    verifiedSlipAmount: parseNumber(request.data?.verifiedSlipAmount),
                    status: 'verified',
                    statusLabel: 'ตรวจสอบสลิปผ่าน',
                    message: String(request.data?.verificationMessage || '').trim(),
                    checkedAt: FieldValue.serverTimestamp(),
                  },
                }),
          }
        : {}),
      audit: {
        createdBy: uid,
        createdByRole: 'cloud_function',
        createdSource: auditSource,
      },
      timestamp: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    batch.set(orderRef, orderPayload);
    const timelineRef = orderRef.collection('timeline').doc();
    batch.set(timelineRef, {
      event: 'order_created',
      eventLabel: createdEventLabel,
      actorId: uid,
      actorRole: 'customer',
      orderId: orderRef.id,
      orderCode,
      status: initialOrderStatus,
      timestamp: FieldValue.serverTimestamp(),
    });

    if (isVerifiedPayment) {
      const verifiedTimelineRef = orderRef.collection('timeline').doc();
      batch.set(verifiedTimelineRef, {
        event: isOmiseVerifiedPayment ? 'payment_omise_verified' : 'payment_slip_verified',
        eventLabel: isOmiseVerifiedPayment
          ? 'ชำระเงินผ่าน Omise แล้ว'
          : 'ระบบตรวจสลิปผ่านแล้ว',
        orderId: orderRef.id,
        paymentGroupId: resolvedPaymentGroupId,
        actorRole: 'system',
        actorId: 'createCheckoutOrders',
        message: isOmiseVerifiedPayment
          ? 'Omise charge successful'
          : String(request.data?.verificationMessage || '').trim(),
        timestamp: FieldValue.serverTimestamp(),
      });
    }

    if (notifyRider && assignedRider) {
      const notificationRef = db.collection('app_notifications').doc();
      batch.set(notificationRef, {
        targetApp: 'van3',
        recipientUid: assignedRider.riderId,
        orderId: orderRef.id,
        title: isVerifiedPayment ? 'ชำระเงินแล้ว มีออเดอร์ใหม่' : 'มีคำสั่งซื้อใหม่',
        body: orderCode
          ? isVerifiedPayment
            ? `ออเดอร์ ${orderCode} ชำระเงินแล้ว`
            : `ออเดอร์ ${orderCode} จาก ${firstItem.shopName}`
          : isVerifiedPayment
            ? 'มีออเดอร์ที่ชำระเงินแล้ว'
            : `มีคำสั่งซื้อใหม่จาก ${firstItem.shopName}`,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
        source: 'van2_customer',
        sourceApp: 'van2_customer',
        action: isVerifiedPayment
          ? 'order_payment_verified'
          : 'order_created_customer_confirmed',
        customerConfirmed: true,
        riderNotifyReady: isVerifiedPayment ? true : riderNotifyReady,
      });
    }

    createdOrderIds.push(orderRef.id);
  }

  if (quoteRef) {
    batch.set(
      quoteRef,
      {
        orderIds: createdOrderIds,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  if (isOmiseVerifiedPayment && paymentSessionId) {
    batch.set(
      db.collection('payment_sessions').doc(paymentSessionId),
      {
        orderIds: createdOrderIds,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  await batch.commit();

  return {
    orderIds: createdOrderIds,
    combinedGrandTotal,
    shopsWithoutRider,
    checkoutQuoteId: checkoutQuoteId || null,
  };
}

async function createNationwideParcelOrdersHandler(request, deps) {
  const {
    db,
    admin,
    FieldValue,
    HttpsError,
    parseNumber,
    loadProductsByIds,
    getPricingRates,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    toFiniteOrNull,
  } = deps;

  const { assertNonAnonymous } = require('./travel_orders');
  assertNonAnonymous(request, HttpsError);

  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนสร้างออเดอร์');
  }

  const uid = request.auth.uid;
  const items = Array.isArray(request.data?.items) ? request.data.items : [];
  const deliveryAddress = request.data?.deliveryAddress || {};
  if (items.length === 0) {
    throw new HttpsError('invalid-argument', 'ไม่มีสินค้าในตะกร้า');
  }

  const paymentGroupId = String(request.data?.paymentGroupId || '').trim();
  const verificationFeedbackId = String(request.data?.verificationFeedbackId || '').trim();
  const slipStoragePath = String(request.data?.slipStoragePath || '').trim();
  if (!paymentGroupId || !verificationFeedbackId) {
    throw new HttpsError('invalid-argument', 'ข้อมูลการชำระเงินไม่ครบ');
  }
  if (!slipStoragePath) {
    throw new HttpsError('invalid-argument', 'ไม่พบไฟล์สลิปสำหรับยืนยันการชำระเงิน');
  }

  const productIds = [
    ...new Set(items.map((item) => String(item?.productId || '').trim()).filter(Boolean)),
  ];
  const products = await loadProductsByIds(productIds);
  const pricingRates = await getPricingRates();
  const resolvedLines = items.map((item) => {
    const productId = String(item?.productId || '').trim();
    const product = products.get(productId);
    if (!product) {
      throw new HttpsError('not-found', `ไม่พบข้อมูลสินค้า ${productId}`);
    }
    return buildResolvedLineItem(item, { ...product, id: productId }, {
      parseNumber,
      isTaxableProduct,
      applyProductMarkupWithRates,
      extractToppings,
      canonicalizeToppingLabel,
      pricingRates,
      toFiniteOrNull,
    });
  });

  const grouped = groupLinesByShop(resolvedLines);
  const shopOrderDrafts = [];
  let combinedGrandTotal = 0;

  for (const [, lines] of grouped.entries()) {
    const firstItem = lines[0];
    const subtotal = lines.reduce((sum, line) => sum + line.unitPrice * line.quantity, 0);
    const merchantSubtotal = lines.reduce(
      (sum, line) => sum + line.merchantUnitPayout * line.quantity,
      0,
    );
    const totalQuantity = lines.reduce((sum, line) => sum + line.quantity, 0);
    const parcel = summarizeNationwideParcel(lines);
    const shippingFee = computeNationwideFee(
      parcel.totalWeightGrams,
      deliveryAddress.postalCode,
      pricingRates,
      parseNumber,
    );
    const grandTotal = subtotal + shippingFee;
    combinedGrandTotal += grandTotal;
    shopOrderDrafts.push({
      lines,
      firstItem,
      subtotal,
      merchantSubtotal,
      totalQuantity,
      parcel,
      shippingFee,
      grandTotal,
    });
  }

  let feedbackRef;
  try {
    feedbackRef = await loadVerifiedStandaloneSlipFeedback(db, HttpsError, {
      uid,
      verificationFeedbackId,
      paymentGroupId,
      slipStoragePath,
      expectedCombinedAmount: combinedGrandTotal,
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('failed-precondition', 'ไม่สามารถยืนยันสลิปได้');
  }

  const userRecord = await admin.auth().getUser(uid);
  const batch = db.batch();
  const orderIds = [];
  const now = new Date();

  for (const draft of shopOrderDrafts) {
    const {
      lines,
      firstItem,
      subtotal,
      merchantSubtotal,
      totalQuantity,
      parcel,
      shippingFee,
      grandTotal,
    } = draft;
    const orderRef = db.collection('orders').doc();
    const orderCode = buildOrderCode('NWP', orderRef.id, now);
    const products = buildProductsPayload(lines);
    const productIdsForOrder = [...new Set(lines.map((line) => line.productId).filter(Boolean))];

    batch.set(orderRef, {
      orderId: orderRef.id,
      orderCode,
      orderType: 'nationwide_parcel',
      fulfillmentType: 'external_courier',
      serviceType: 'nationwide_parcel',
      status: 'accepted',
      statusLabel: 'ส่งทั่วประเทศ - รอร้านยืนยัน',
      shippingProvider: 'manual',
      shippingProviderLabel: 'รอเชื่อมต่อ ShipPop',
      shippingStatus: 'awaiting_booking',
      shippingStatusLabel: 'รอจองขนส่ง',
      paymentMethod: 'promptpay_qr',
      paymentMethodLabel: 'สแกนจ่าย',
      paymentStatus: 'verified',
      paymentStatusLabel: 'ชำระเงินแล้ว',
      paymentGroupId,
      paymentSubmittedAt: FieldValue.serverTimestamp(),
      paymentSlip: {
        storagePath: String(request.data?.slipStoragePath || '').trim(),
        downloadUrl: String(request.data?.slipDownloadUrl || '').trim(),
        fileName: String(request.data?.slipFileName || 'slip.jpg').trim(),
        contentType: request.data?.slipContentType || null,
        sizeBytes: parseNumber(request.data?.slipSizeBytes),
        uploadedBy: uid,
        uploadedAt: FieldValue.serverTimestamp(),
      },
      paymentVerification: {
        provider: 'slipok',
        providerLabel: 'Slip OK',
        feedbackId: verificationFeedbackId,
        paymentGroupId,
        expectedCombinedAmount: parseNumber(request.data?.expectedCombinedAmount),
        verifiedSlipAmount: parseNumber(request.data?.verifiedSlipAmount),
        status: 'verified',
        statusLabel: 'ตรวจสอบสลิปผ่าน',
        message: String(request.data?.verificationMessage || '').trim(),
        checkedAt: FieldValue.serverTimestamp(),
      },
      sourceApp: 'van2_customer',
      customerId: uid,
      customerEmail: userRecord.email || null,
      customerPhone: userRecord.phoneNumber || null,
      customerSnapshot: {
        uid,
        email: userRecord.email || null,
        phoneNumber: userRecord.phoneNumber || null,
      },
      shopOwnerId: firstItem.shopId,
      shopId: firstItem.shopId,
      shopName: firstItem.shopName,
      deliveryAddress,
      itemCount: lines.length,
      totalQuantity,
      products,
      productIds: productIdsForOrder,
      parcel,
      shippingQuote: {
        provider: 'manual',
        providerLabel: 'รอเชื่อมต่อ ShipPop',
        serviceLevel: 'manual_standard',
        shippingFee,
        isManualEstimate: true,
        parcel,
      },
      totalPrice: subtotal,
      subtotal,
      merchantSubtotal,
      shippingFee,
      grandTotal,
      audit: {
        createdBy: uid,
        createdByRole: 'cloud_function',
        createdSource: 'cloud_function_nationwide',
      },
      timestamp: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const timelineRef = orderRef.collection('timeline').doc();
    batch.set(timelineRef, {
      event: 'nationwide_order_created',
      eventLabel: 'ลูกค้าชำระเงินแล้ว ระบบสร้างออเดอร์ส่งทั่วประเทศ',
      actorRole: 'customer',
      actorId: uid,
      timestamp: FieldValue.serverTimestamp(),
    });

    const notificationRef = db.collection('app_notifications').doc();
    batch.set(notificationRef, {
      targetApp: 'van1',
      recipientUid: firstItem.shopId,
      orderId: orderRef.id,
      title: 'ออเดอร์ส่งทั่วประเทศใหม่',
      body: `ใช้ขนส่งภายนอก • ${lines.length} รายการ • ยอดรวม ฿${grandTotal.toFixed(0)}`,
      action: 'order_accepted',
      sourceApp: 'van2_customer',
      orderDecision: true,
      orderType: 'nationwide_parcel',
      fulfillmentType: 'external_courier',
      shippingProvider: 'manual',
      shippingProviderLabel: 'รอเชื่อมต่อ ShipPop',
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    orderIds.push(orderRef.id);
  }

  await batch.commit();

  try {
    await markStandaloneSlipFeedbackConsumed(db, FieldValue, feedbackRef, orderIds);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message === 'slip_already_consumed') {
      throw new HttpsError('failed-precondition', 'สลิปนี้ถูกใช้สร้างออเดอร์แล้ว');
    }
    throw new HttpsError('internal', 'สร้างออเดอร์แล้ว แต่บันทึกสถานะสลิปไม่สำเร็จ');
  }

  return { orderIds, combinedGrandTotal };
}

module.exports = {
  CHECKOUT_QUOTES_COLLECTION,
  computeVan2CartTotals,
  persistCheckoutQuote,
  createCheckoutOrdersHandler,
  createNationwideParcelOrdersHandler,
};
