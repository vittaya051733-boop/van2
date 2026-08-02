const { HttpsError, onCall } = require('firebase-functions/v2/https');

const COUPONS_COLLECTION = 'coupons';
const CUSTOMER_USERS_COLLECTION = 'customer_users';
const CLAIMED_COUPONS_SUBCOLLECTION = 'claimed_coupons';

function parseNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function parseTimestampMs(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function isWithinSchedule(conditions = {}, nowMs = Date.now()) {
  const startMs = parseTimestampMs(conditions.startAt);
  const endMs = parseTimestampMs(conditions.endAt);
  if (startMs != null && nowMs < startMs) {
    return false;
  }
  if (endMs != null && nowMs > endMs) {
    return false;
  }
  return true;
}

function formatDiscountSummary(discount = {}) {
  const type = String(discount.type || 'fixed').toLowerCase();
  const value = parseNumber(discount.value);
  if (type === 'percent') {
    return `ลด ${value}%`;
  }
  if (type === 'free_shipping') {
    return 'ฟรีค่าส่ง';
  }
  return `ลด ฿${Math.round(value)}`;
}

function createCouponClaimsHandlers({
  db,
  FieldValue,
  DEFAULT_REGION,
  enforceAppCheck = true,
}) {
  async function claimCouponCore(userId, couponId) {
    const normalizedCouponId = String(couponId || '').trim();
    if (!normalizedCouponId) {
      throw new HttpsError('invalid-argument', 'ต้องระบุ couponId');
    }

    const couponRef = db.collection(COUPONS_COLLECTION).doc(normalizedCouponId);
    const claimedRef = db
      .collection(CUSTOMER_USERS_COLLECTION)
      .doc(userId)
      .collection(CLAIMED_COUPONS_SUBCOLLECTION)
      .doc(normalizedCouponId);

    return db.runTransaction(async (transaction) => {
      const couponSnap = await transaction.get(couponRef);
      if (!couponSnap.exists) {
        throw new HttpsError('not-found', 'ไม่พบคูปองนี้');
      }

      const coupon = couponSnap.data() || {};
      const distribution = String(coupon.distribution || 'manual_code').toLowerCase();
      if (distribution !== 'self_claim') {
        throw new HttpsError('failed-precondition', 'คูปองนี้ไม่สามารถกดรับเองได้');
      }
      if (coupon.active === false) {
        throw new HttpsError('failed-precondition', 'คูปองนี้ปิดใช้งานแล้ว');
      }

      const conditions = coupon.conditions || {};
      if (!isWithinSchedule(conditions)) {
        throw new HttpsError('failed-precondition', 'คูปองนี้หมดเขตหรือยังไม่เริ่ม');
      }

      const maxClaimsTotal = Math.floor(parseNumber(conditions.maxClaimsTotal) || 0);
      const claimCount = Math.floor(parseNumber(coupon.claimCount) || 0);
      if (maxClaimsTotal > 0 && claimCount >= maxClaimsTotal) {
        throw new HttpsError('resource-exhausted', 'โควต้ารับคูปองเต็มแล้ว');
      }

      const existingClaimSnap = await transaction.get(claimedRef);
      if (existingClaimSnap.exists) {
        const existing = existingClaimSnap.data() || {};
        if (String(existing.status || 'active') === 'used') {
          throw new HttpsError('failed-precondition', 'คุณใช้คูปองนี้แล้ว');
        }
        return {
          alreadyClaimed: true,
          couponId: normalizedCouponId,
          code: String(existing.code || coupon.code || '').trim().toUpperCase(),
          name: String(existing.name || coupon.name || 'คูปอง'),
          shortLabel: String(existing.shortLabel || coupon.display?.shortLabel || coupon.name || ''),
          discountSummary: String(existing.discountSummary || formatDiscountSummary(coupon.discount)),
          imageUrl: String(existing.imageUrl || coupon.display?.imageUrl || ''),
        };
      }

      const display = coupon.display || {};
      const code = String(coupon.code || '').trim().toUpperCase();
      if (!code) {
        throw new HttpsError('failed-precondition', 'คูปองนี้ยังไม่มีรหัส');
      }

      const now = FieldValue.serverTimestamp();
      const discountSummary = formatDiscountSummary(coupon.discount);
      const walletPayload = {
        couponId: normalizedCouponId,
        code,
        name: String(coupon.name || 'คูปอง'),
        shortLabel: String(display.shortLabel || coupon.name || 'คูปอง'),
        discountSummary,
        imageUrl: String(display.imageUrl || ''),
        claimedAt: now,
        expiresAt: conditions.endAt || null,
        status: 'active',
      };

      transaction.set(claimedRef, walletPayload);
      transaction.set(
        couponRef,
        {
          claimCount: FieldValue.increment(1),
          updatedAt: now,
        },
        { merge: true },
      );

      return {
        alreadyClaimed: false,
        couponId: normalizedCouponId,
        code,
        name: walletPayload.name,
        shortLabel: walletPayload.shortLabel,
        discountSummary,
        imageUrl: walletPayload.imageUrl,
      };
    });
  }

  function markClaimedCouponsUsed(batch, userId, discountLines, now) {
    if (!userId || !Array.isArray(discountLines)) {
      return;
    }

    for (const line of discountLines) {
      const kind = String(line?.kind || '').toLowerCase();
      if (kind !== 'coupon') {
        continue;
      }
      const couponId = String(line?.id || '').trim();
      if (!couponId) {
        continue;
      }

      const claimedRef = db
        .collection(CUSTOMER_USERS_COLLECTION)
        .doc(userId)
        .collection(CLAIMED_COUPONS_SUBCOLLECTION)
        .doc(couponId);

      batch.set(
        claimedRef,
        {
          status: 'used',
          usedAt: now,
        },
        { merge: true },
      );
    }
  }

  const claimCoupon = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck,
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const couponId = String(request.data?.couponId || '').trim();
      return claimCouponCore(request.auth.uid, couponId);
    },
  );

  return {
    claimCoupon,
    claimCouponCore,
    markClaimedCouponsUsed,
    formatDiscountSummary,
  };
}

module.exports = {
  createCouponClaimsHandlers,
  COUPONS_COLLECTION,
  CUSTOMER_USERS_COLLECTION,
  CLAIMED_COUPONS_SUBCOLLECTION,
};
