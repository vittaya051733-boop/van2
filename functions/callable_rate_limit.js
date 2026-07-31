function readClientIp(request) {
  const rawRequest = request?.rawRequest;
  const forwarded = rawRequest?.headers?.['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    return String(forwarded[0]).trim();
  }
  return String(rawRequest?.ip || 'unknown').trim() || 'unknown';
}

async function assertCallableRateLimit(db, admin, HttpsError, {
  key,
  maxAttempts,
  windowMs,
  message = 'คำขอมากเกินไป กรุณารอสักครู่แล้วลองใหม่',
}) {
  const normalizedKey = String(key || '').trim();
  if (!normalizedKey) {
    return;
  }

  const limit = Math.max(1, Math.floor(Number(maxAttempts) || 1));
  const window = Math.max(1000, Math.floor(Number(windowMs) || 60000));
  const ref = db.collection('auth_rate_limits').doc(normalizedKey);
  const now = Date.now();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() || {};
    const windowStartMs = data.windowStart?.toMillis?.() || 0;
    const count = Number(data.count || 0);

    if (!windowStartMs || now - windowStartMs >= window) {
      transaction.set(ref, {
        count: 1,
        windowStart: admin.firestore.Timestamp.fromMillis(now),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (count >= limit) {
      throw new HttpsError('resource-exhausted', message);
    }

    transaction.set(
      ref,
      {
        count: count + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

module.exports = {
  readClientIp,
  assertCallableRateLimit,
};
