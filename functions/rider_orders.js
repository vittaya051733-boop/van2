const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { assertApprovedRiderOutsideTransaction } = require('./rider_guard');

let db;
let DEFAULT_REGION;

function init(deps) {
  db = deps.db;
  DEFAULT_REGION = deps.DEFAULT_REGION;
}

function serializeFirestoreValue(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (value && typeof value.toDate === 'function') {
    return value.toMillis();
  }
  if (Array.isArray(value)) {
    return value.map((entry) => serializeFirestoreValue(entry));
  }
  if (typeof value === 'object') {
    const output = {};
    for (const [key, nested] of Object.entries(value)) {
      output[key] = serializeFirestoreValue(nested);
    }
    return output;
  }
  return value;
}

function registerHandlers() {
  const listRiderOrders = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const uid = request.auth.uid.trim();
      if (!uid) {
        throw new HttpsError('invalid-argument', 'ไม่พบ uid');
      }

      await assertApprovedRiderOutsideTransaction(uid);

      const snapshot = await db
        .collection('orders')
        .where('driverId', '==', uid)
        .get();

      const orders = snapshot.docs.map((doc) => ({
        id: doc.id,
        data: serializeFirestoreValue(doc.data()) || {},
      }));

      return {
        orders,
        count: orders.length,
        riderUid: uid,
      };
    },
  );

  return { listRiderOrders };
}

module.exports = {
  init,
  registerHandlers,
};
