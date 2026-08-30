const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { assertVan4Admin } = require('./social/admin_guard');

const ORDERS_COLLECTION = 'orders';
const ORDER_CLAIMS_COLLECTION = 'order_claims';
const COUPONS_COLLECTION = 'coupons';
const CUSTOMER_USERS_COLLECTION = 'customer_users';
const CLAIMED_COUPONS_SUBCOLLECTION = 'claimed_coupons';
const PRODUCTS_COLLECTION = 'products';
const APP_NOTIFICATIONS_COLLECTION = 'app_notifications';

const KIND_REPLACEMENT = 'replacement';
const KIND_CREDIT = 'credit';
const REASON_KEYS = new Set(['mismatch', 'damaged', 'wrong_item', 'other']);

let db;
let FieldValue;
let DEFAULT_REGION;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  DEFAULT_REGION = deps.DEFAULT_REGION || 'asia-southeast1';
}

function readString(value) {
  return String(value == null ? '' : value).trim();
}

function parseNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function roundMoney(value) {
  return Math.round(parseNumber(value) * 100) / 100;
}

function readFiniteStock(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function buildOrderCode(prefix, orderId, now = new Date()) {
  const y = String(now.getFullYear()).padStart(4, '0');
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const suffix = String(orderId).substring(0, 6).toUpperCase();
  return `${prefix}-${y}${m}${d}-${suffix}`;
}

function reasonLabel(reason) {
  switch (reason) {
    case 'mismatch':
      return 'สินค้าไม่ตรงปก';
    case 'damaged':
      return 'สินค้าเสียหาย';
    case 'wrong_item':
      return 'ส่งผิดชิ้น';
    default:
      return 'เคลมสินค้า';
  }
}

function readOriginalProducts(orderData) {
  const raw = orderData.products || orderData.items;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .filter((item) => item && typeof item === 'object')
    .map((item) => ({
      productId: readString(item.productId),
      name: readString(item.name || item.productName || item.title) || 'สินค้า',
      quantity: Math.max(1, Math.floor(parseNumber(item.quantity) || 1)),
      unitPrice: roundMoney(item.unitPrice ?? item.price),
      merchantUnitPayout: roundMoney(item.merchantUnitPayout ?? item.unitPrice ?? item.price),
      merchantLinePayout: roundMoney(item.merchantLinePayout),
      lineTotal: roundMoney(item.lineTotal ?? item.total),
      imageUrl: readString(item.imageUrl || item.photoUrl || item.productImage),
      variantId: readString(item.variantId),
      selectedSize: readString(item.selectedSize),
      selectedColor: readString(item.selectedColor),
      selectedToppings: Array.isArray(item.selectedToppings) ? item.selectedToppings : [],
      note: readString(item.note || item.notes),
      raw: item,
    }));
}

function parseRequestedItems(rawItems) {
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    return [];
  }
  const items = [];
  for (const raw of rawItems) {
    if (!raw || typeof raw !== 'object') {
      continue;
    }
    const productId = readString(raw.productId);
    const quantity = Math.max(1, Math.floor(parseNumber(raw.quantity) || 1));
    if (!productId || quantity > 99) {
      continue;
    }
    items.push({ productId, quantity });
  }
  return items;
}

function firstImageUrl(productData) {
  const urls = productData?.imageUrls;
  if (Array.isArray(urls)) {
    const first = urls.find((url) => readString(url));
    if (first) {
      return readString(first);
    }
  }
  return readString(productData?.imageUrl || productData?.photoUrl);
}

function notifyPayload({
  targetApp,
  recipientUid,
  title,
  body,
  action,
  orderId,
  source,
}) {
  return {
    targetApp,
    recipientUid,
    title,
    body,
    action,
    orderId: orderId || null,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
    source: source || 'van4_admin',
    sourceApp: 'van4_admin',
  };
}

async function buildReplacementLines(orderData, requestedItems, platformPaysShop) {
  const originalLines = readOriginalProducts(orderData);
  const shopOwnerId = readString(orderData.shopOwnerId || orderData.shopId);
  const lines = [];

  for (const requested of requestedItems) {
    const original = originalLines.find((line) => line.productId === requested.productId);
    if (original) {
      const unitPrice = original.unitPrice;
      const merchantUnit = platformPaysShop ? original.merchantUnitPayout || unitPrice : 0;
      lines.push({
        productId: original.productId,
        name: original.name,
        quantity: requested.quantity,
        unitPrice,
        merchantUnitPayout: merchantUnit,
        merchantLinePayout: roundMoney(merchantUnit * requested.quantity),
        lineTotal: roundMoney(unitPrice * requested.quantity),
        imageUrl: original.imageUrl,
        variantId: original.variantId,
        selectedSize: original.selectedSize,
        selectedColor: original.selectedColor,
        selectedToppings: original.selectedToppings,
        note: original.note,
      });
      continue;
    }

    const productSnap = await db.collection(PRODUCTS_COLLECTION).doc(requested.productId).get();
    if (!productSnap.exists) {
      throw new HttpsError('not-found', `ไม่พบสินค้า ${requested.productId}`);
    }
    const product = productSnap.data() || {};
    const ownerUid = readString(product.ownerUid || product.shopOwnerId);
    if (ownerUid && shopOwnerId && ownerUid !== shopOwnerId) {
      throw new HttpsError('failed-precondition', 'เลือกได้เฉพาะสินค้าของร้านในออเดอร์เดิม');
    }
    const unitPrice = roundMoney(product.price ?? product.unitPrice);
    const merchantUnit = platformPaysShop ? unitPrice : 0;
    const imageUrl = firstImageUrl(product);
    lines.push({
      productId: requested.productId,
      name: readString(product.name) || 'สินค้า',
      quantity: requested.quantity,
      unitPrice,
      merchantUnitPayout: merchantUnit,
      merchantLinePayout: roundMoney(merchantUnit * requested.quantity),
      lineTotal: roundMoney(unitPrice * requested.quantity),
      imageUrl,
      variantId: '',
      selectedSize: '',
      selectedColor: '',
      selectedToppings: [],
      note: '',
    });
  }

  if (lines.length === 0) {
    throw new HttpsError('invalid-argument', 'ต้องเลือกสินค้าอย่างน้อย 1 รายการ');
  }
  return lines;
}

function toProductsPayload(lines) {
  return lines.map((line) => {
    const imageUrl = readString(line.imageUrl);
    return {
      productId: line.productId,
      name: line.name,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      merchantUnitPayout: line.merchantUnitPayout,
      merchantLinePayout: line.merchantLinePayout,
      lineTotal: line.lineTotal,
      ...(imageUrl ? { imageUrl, productImage: imageUrl } : {}),
      ...(line.variantId ? { variantId: line.variantId } : {}),
      ...(line.selectedSize ? { selectedSize: line.selectedSize } : {}),
      ...(line.selectedColor ? { selectedColor: line.selectedColor } : {}),
      ...(Array.isArray(line.selectedToppings) && line.selectedToppings.length
        ? { selectedToppings: line.selectedToppings }
        : {}),
      ...(line.note ? { note: line.note } : {}),
    };
  });
}

async function decrementStock(transaction, lines) {
  const qtyByProduct = new Map();
  for (const line of lines) {
    qtyByProduct.set(line.productId, (qtyByProduct.get(line.productId) || 0) + line.quantity);
  }

  const snapshots = [];
  for (const [productId, qty] of qtyByProduct.entries()) {
    const productRef = db.collection(PRODUCTS_COLLECTION).doc(productId);
    const snap = await transaction.get(productRef);
    snapshots.push({ productId, qty, productRef, snap });
  }

  for (const { productId, qty, productRef, snap } of snapshots) {
    if (!snap.exists) {
      continue;
    }
    const tracked = readFiniteStock(snap.data()?.stock);
    if (tracked === null) {
      continue;
    }
    if (tracked < qty) {
      throw new HttpsError('failed-precondition', `สต๊อกไม่พอสำหรับสินค้า ${productId}`);
    }
    transaction.update(productRef, {
      stock: FieldValue.increment(-qty),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

async function resolveReplacement({ adminUser, originalOrderId, originalRef, originalData, requestedItems, reason, platformPaysShop, shopPayoutAmount }) {
  const customerId = readString(originalData.customerId);
  const shopOwnerId = readString(originalData.shopOwnerId || originalData.shopId);
  if (!customerId || !shopOwnerId) {
    throw new HttpsError('failed-precondition', 'ออเดอร์เดิมไม่มีลูกค้าหรือร้าน');
  }

  const lines = await buildReplacementLines(originalData, requestedItems, platformPaysShop);
  const products = toProductsPayload(lines);
  const subtotal = roundMoney(lines.reduce((sum, line) => sum + line.lineTotal, 0));
  let merchantSubtotal = platformPaysShop
    ? roundMoney(lines.reduce((sum, line) => sum + line.merchantLinePayout, 0))
    : 0;
  if (platformPaysShop) {
    const overrideAmount = roundMoney(shopPayoutAmount);
    if (overrideAmount > 0) {
      merchantSubtotal = overrideAmount;
    } else if (merchantSubtotal <= 0) {
      throw new HttpsError('invalid-argument', 'ต้องระบุเครดิตให้ร้านรอบ 2 มากกว่า 0');
    }
  }
  const shippingFee = roundMoney(originalData.shippingFee ?? originalData.deliveryFee);
  const totalQuantity = lines.reduce((sum, line) => sum + line.quantity, 0);
  const productIds = [...new Set(lines.map((line) => line.productId))];
  const now = new Date();

  const claimRef = db.collection(ORDER_CLAIMS_COLLECTION).doc();
  const orderRef = db.collection(ORDERS_COLLECTION).doc();
  const orderCode = buildOrderCode('CLM', orderRef.id, now);
  const label = reasonLabel(reason);

  const settlement = {};
  if (shippingFee > 0) {
    settlement.riderPayout = {
      amount: shippingFee,
      status: 'pending',
      fundingSource: 'platform_float',
    };
  }
  if (merchantSubtotal > 0) {
    settlement.shopPayout = {
      amount: merchantSubtotal,
      status: 'pending',
      fundingSource: 'platform_float',
    };
  }

  const replacementPayload = {
    orderId: orderRef.id,
    orderCode,
    orderType: 'claim_replacement',
    originOrderId: originalOrderId,
    claimId: claimRef.id,
    status: 'awaiting_rider',
    statusLabel: 'awaiting_nearest_rider',
    customerConfirmed: true,
    customerConfirmedAt: FieldValue.serverTimestamp(),
    riderNotifyReady: true,
    paymentMethod: 'claim_comp',
    paymentMethodLabel: 'เคลมทดแทน (ไม่คิดเงิน)',
    paymentStatus: 'verified',
    paymentStatusLabel: 'ไม่คิดเงิน — เคลมทดแทน',
    sourceApp: 'van4_admin',
    customerId,
    customerEmail: originalData.customerEmail || null,
    customerPhone: originalData.customerPhone || null,
    customerSnapshot: originalData.customerSnapshot || {
      uid: customerId,
    },
    shopOwnerId,
    shopId: shopOwnerId,
    shopName: originalData.shopName || null,
    ...(originalData.shopSnapshot ? { shopSnapshot: originalData.shopSnapshot } : {}),
    ...(originalData.shopImageUrl ? { shopImageUrl: originalData.shopImageUrl } : {}),
    ...(originalData.shopLatitude != null ? { shopLatitude: originalData.shopLatitude } : {}),
    ...(originalData.shopLongitude != null ? { shopLongitude: originalData.shopLongitude } : {}),
    ...(originalData.shopLocation ? { shopLocation: originalData.shopLocation } : {}),
    driverId: null,
    customerLocation: originalData.customerLocation || null,
    deliverySnapshot: originalData.deliverySnapshot || originalData.customerLocation || null,
    itemCount: lines.length,
    totalQuantity,
    products,
    productIds,
    totalPrice: subtotal,
    subtotal,
    merchantSubtotal,
    shippingFee,
    serviceFee: 0,
    multiShopCollectionFee: 0,
    grandTotal: 0,
    claimReason: reason,
    claimReasonLabel: label,
    ...(Object.keys(settlement).length ? { settlement } : {}),
    audit: {
      createdBy: adminUser.uid,
      createdByRole: 'admin',
      createdSource: 'adminResolveClaim',
    },
    timestamp: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.runTransaction(async (transaction) => {
    const freshOriginal = await transaction.get(originalRef);
    if (!freshOriginal.exists) {
      throw new HttpsError('not-found', 'ไม่พบออเดอร์เดิม');
    }
    const freshData = freshOriginal.data() || {};
    const existingStatus = readString(freshData.claimStatus).toLowerCase();
    if (existingStatus === 'replaced' || existingStatus === 'credited') {
      throw new HttpsError('failed-precondition', 'ออเดอร์นี้เคลมไปแล้ว');
    }

    await decrementStock(transaction, lines);

    transaction.set(claimRef, {
      originalOrderId,
      customerId,
      shopOwnerId,
      kind: KIND_REPLACEMENT,
      reason,
      reasonLabel: label,
      productIds,
      adminUid: adminUser.uid,
      adminEmail: adminUser.email,
      replacementOrderId: orderRef.id,
      status: 'resolved',
      platformPaysShop: platformPaysShop === true,
      shopPayoutAmount: platformPaysShop ? merchantSubtotal : null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(orderRef, replacementPayload);
    transaction.set(orderRef.collection('timeline').doc(), {
      event: 'claim_replacement_created',
      eventLabel: `สร้างออเดอร์ทดแทน (${label})`,
      actorId: adminUser.uid,
      actorRole: 'admin',
      orderId: orderRef.id,
      originOrderId: originalOrderId,
      status: 'awaiting_rider',
      timestamp: FieldValue.serverTimestamp(),
    });
    transaction.set(
      originalRef,
      {
        claimStatus: 'replaced',
        claimId: claimRef.id,
        replacementOrderId: orderRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(originalRef.collection('timeline').doc(), {
      event: 'claim_replacement_issued',
      eventLabel: `แอดมินส่งสินค้าทดแทน ${orderCode}`,
      actorId: adminUser.uid,
      actorRole: 'admin',
      replacementOrderId: orderRef.id,
      timestamp: FieldValue.serverTimestamp(),
    });
    transaction.set(
      db.collection(APP_NOTIFICATIONS_COLLECTION).doc(),
      notifyPayload({
        targetApp: 'van2',
        recipientUid: customerId,
        title: 'ส่งสินค้าทดแทนให้แล้ว',
        body: `ออเดอร์ ${orderCode} ไม่คิดเงินเพิ่ม — ${label}`,
        action: 'claim_replacement_created',
        orderId: orderRef.id,
      }),
    );
    transaction.set(
      db.collection(APP_NOTIFICATIONS_COLLECTION).doc(),
      notifyPayload({
        targetApp: 'van1',
        recipientUid: shopOwnerId,
        title: 'มีออเดอร์ทดแทน (เคลม)',
        body: `ออเดอร์ ${orderCode} จากเคลม ${readString(originalData.orderCode) || originalOrderId}`,
        action: 'claim_replacement_created',
        orderId: orderRef.id,
      }),
    );
  });

  return {
    kind: KIND_REPLACEMENT,
    claimId: claimRef.id,
    replacementOrderId: orderRef.id,
    orderCode,
  };
}

async function resolveCredit({ adminUser, originalOrderId, originalRef, originalData, requestedItems, reason, creditAmount }) {
  const customerId = readString(originalData.customerId);
  if (!customerId) {
    throw new HttpsError('failed-precondition', 'ออเดอร์เดิมไม่มีลูกค้า');
  }

  const originalLines = readOriginalProducts(originalData);
  let defaultAmount = roundMoney(originalData.grandTotal ?? originalData.totalPrice);
  if (requestedItems.length > 0) {
    defaultAmount = 0;
    for (const requested of requestedItems) {
      const original = originalLines.find((line) => line.productId === requested.productId);
      if (original) {
        const unit = original.unitPrice || roundMoney(original.lineTotal / Math.max(1, original.quantity));
        defaultAmount += unit * requested.quantity;
      }
    }
    defaultAmount = roundMoney(defaultAmount);
  }
  const amount = roundMoney(creditAmount > 0 ? creditAmount : defaultAmount);
  if (amount <= 0) {
    throw new HttpsError('invalid-argument', 'ยอดคูปองเครดิตต้องมากกว่า 0');
  }

  const label = reasonLabel(reason);
  const claimRef = db.collection(ORDER_CLAIMS_COLLECTION).doc();
  const couponRef = db.collection(COUPONS_COLLECTION).doc();
  const code = `CLAIM${String(couponRef.id).replace(/[^A-Za-z0-9]/g, '').slice(0, 8).toUpperCase()}`;
  const claimedRef = db
    .collection(CUSTOMER_USERS_COLLECTION)
    .doc(customerId)
    .collection(CLAIMED_COUPONS_SUBCOLLECTION)
    .doc(couponRef.id);
  const productIds = requestedItems.map((item) => item.productId).filter(Boolean);
  const discountSummary = `ลด ฿${Math.round(amount)}`;

  await db.runTransaction(async (transaction) => {
    const freshOriginal = await transaction.get(originalRef);
    if (!freshOriginal.exists) {
      throw new HttpsError('not-found', 'ไม่พบออเดอร์เดิม');
    }
    const freshData = freshOriginal.data() || {};
    const existingStatus = readString(freshData.claimStatus).toLowerCase();
    if (existingStatus === 'replaced' || existingStatus === 'credited') {
      throw new HttpsError('failed-precondition', 'ออเดอร์นี้เคลมไปแล้ว');
    }

    transaction.set(couponRef, {
      code,
      name: `เครดิตเคลม ${readString(originalData.orderCode) || originalOrderId}`,
      active: true,
      distribution: 'admin_grant',
      assigneeUid: customerId,
      originOrderId: originalOrderId,
      claimId: claimRef.id,
      source: 'claim_credit',
      discount: {
        type: 'fixed',
        value: amount,
        applyTo: 'grand_total',
      },
      conditions: {
        maxRedemptionsTotal: 1,
        maxRedemptionsPerUser: 1,
        maxClaimsTotal: 1,
        assigneeUid: customerId,
      },
      display: {
        shortLabel: `เครดิตเคลม ฿${Math.round(amount)}`,
        presentation: 'inline',
      },
      claimCount: 1,
      stackableWithPromotion: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(claimedRef, {
      couponId: couponRef.id,
      code,
      name: `เครดิตเคลม ฿${Math.round(amount)}`,
      shortLabel: `เครดิตเคลม ฿${Math.round(amount)}`,
      discountSummary,
      imageUrl: '',
      claimedAt: FieldValue.serverTimestamp(),
      expiresAt: null,
      status: 'active',
      source: 'claim_credit',
      originOrderId: originalOrderId,
    });
    transaction.set(claimRef, {
      originalOrderId,
      customerId,
      shopOwnerId: readString(originalData.shopOwnerId || originalData.shopId) || null,
      kind: KIND_CREDIT,
      reason,
      reasonLabel: label,
      productIds,
      adminUid: adminUser.uid,
      adminEmail: adminUser.email,
      couponId: couponRef.id,
      couponCode: code,
      creditAmount: amount,
      status: 'resolved',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(
      originalRef,
      {
        claimStatus: 'credited',
        claimId: claimRef.id,
        claimCreditCouponId: couponRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(originalRef.collection('timeline').doc(), {
      event: 'claim_credit_issued',
      eventLabel: `แอดมินให้คูปองเครดิต ${code} ฿${Math.round(amount)}`,
      actorId: adminUser.uid,
      actorRole: 'admin',
      couponId: couponRef.id,
      timestamp: FieldValue.serverTimestamp(),
    });
    transaction.set(
      db.collection(APP_NOTIFICATIONS_COLLECTION).doc(),
      notifyPayload({
        targetApp: 'van2',
        recipientUid: customerId,
        title: 'ได้รับคูปองเครดิตเคลม',
        body: `ใช้โค้ด ${code} ลด ฿${Math.round(amount)} ในออเดอร์ถัดไป`,
        action: 'claim_credit_granted',
        orderId: originalOrderId,
      }),
    );
  });

  return {
    kind: KIND_CREDIT,
    claimId: claimRef.id,
    couponId: couponRef.id,
    couponCode: code,
    creditAmount: amount,
  };
}

function registerHandlers() {
  const adminResolveClaim = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      const adminUser = await assertVan4Admin(request);
      const originalOrderId = readString(request.data?.originalOrderId || request.data?.orderId);
      const kind = readString(request.data?.kind).toLowerCase();
      const reasonRaw = readString(request.data?.reason).toLowerCase() || 'other';
      const reason = REASON_KEYS.has(reasonRaw) ? reasonRaw : 'other';
      const requestedItems = parseRequestedItems(request.data?.items);
      const platformPaysShop = request.data?.platformPaysShop === true;
      const creditAmount = parseNumber(request.data?.creditAmount);
      const shopPayoutAmount = parseNumber(request.data?.shopPayoutAmount);

      if (!originalOrderId) {
        throw new HttpsError('invalid-argument', 'ต้องระบุ originalOrderId');
      }
      if (kind !== KIND_REPLACEMENT && kind !== KIND_CREDIT) {
        throw new HttpsError('invalid-argument', 'kind ต้องเป็น replacement หรือ credit');
      }

      const originalRef = db.collection(ORDERS_COLLECTION).doc(originalOrderId);
      const originalSnap = await originalRef.get();
      if (!originalSnap.exists) {
        throw new HttpsError('not-found', 'ไม่พบออเดอร์เดิม');
      }
      const originalData = originalSnap.data() || {};
      const existingStatus = readString(originalData.claimStatus).toLowerCase();
      if (existingStatus === 'replaced' || existingStatus === 'credited') {
        throw new HttpsError('failed-precondition', 'ออเดอร์นี้เคลมไปแล้ว');
      }
      if (readString(originalData.orderType) === 'claim_replacement') {
        throw new HttpsError('failed-precondition', 'ไม่สามารถเคลมออเดอร์ทดแทนซ้ำได้');
      }

      if (kind === KIND_REPLACEMENT) {
        if (requestedItems.length === 0) {
          throw new HttpsError('invalid-argument', 'ต้องเลือกสินค้าที่จะส่งทดแทน');
        }
        return resolveReplacement({
          adminUser,
          originalOrderId,
          originalRef,
          originalData,
          requestedItems,
          reason,
          platformPaysShop,
          shopPayoutAmount,
        });
      }

      return resolveCredit({
        adminUser,
        originalOrderId,
        originalRef,
        originalData,
        requestedItems,
        reason,
        creditAmount,
      });
    },
  );

  return { adminResolveClaim };
}

module.exports = {
  init,
  registerHandlers,
};
