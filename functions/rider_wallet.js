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
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isPayAtDestinationOrder(orderData) {
  if (!orderData || typeof orderData !== 'object') {
    return false;
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

function resolveOrderShippingFee(orderData) {
  return (
    readDouble(orderData.shippingFee) ??
    readDouble(orderData.deliveryFee) ??
    readDouble(orderData.deliveryCharge) ??
    readDouble(orderData.shipping) ??
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

async function sumCreditBalance(tx, uid) {
  const creditsQuery = db.collection('credits').where('uid', '==', uid);
  const snapshot = await tx.get(creditsQuery);
  let total = 0;
  for (const doc of snapshot.docs) {
    total += readDouble(doc.data()?.amount) ?? 0;
  }
  return total;
}

function registerHandlers() {
  const acceptRiderOrder = onCall(
    { region: DEFAULT_REGION },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const uid = String(request.auth.uid).trim();
      const orderId = String(request.data?.orderId || '').trim();
      if (!orderId) {
        throw new HttpsError('invalid-argument', 'กรุณาระบุ orderId');
      }

      const orderRef = db.collection('orders').doc(orderId);
      let holdAmount = 0;

      await db.runTransaction(async (tx) => {
        const orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) {
          throw new HttpsError('not-found', 'ไม่พบออเดอร์');
        }

        const order = orderSnap.data() || {};
        const status = String(order.status || '').trim();
        if (status && status !== 'pending' && status !== 'awaiting_rider') {
          throw new HttpsError(
            'failed-precondition',
            `ออเดอร์ไม่อยู่ในสถานะรอรับงาน (สถานะ: ${status || 'unknown'})`,
          );
        }

        const driverId = String(order.driverId || '').trim();
        if (driverId && driverId !== uid) {
          throw new HttpsError('permission-denied', 'ออเดอร์นี้ถูกจองโดยไรเดอร์คนอื่นแล้ว');
        }

        if (isPayAtDestinationOrder(order)) {
          holdAmount = resolvePayAtDestinationHoldAmount(order);
        }

        if (holdAmount > 0) {
          const balance = await sumCreditBalance(tx, uid);
          if (balance < holdAmount) {
            throw new HttpsError(
              'failed-precondition',
              `เครดิตไม่พอ (ต้องการ ${holdAmount.toFixed(2)} บาท)`,
            );
          }

          const creditDocId = `order_pay_at_destination_${orderId}_${uid}`;
          const creditRef = db.collection('credits').doc(creditDocId);
          const creditSnap = await tx.get(creditRef);
          if (creditSnap.exists) {
            throw new HttpsError('already-exists', 'มีการหักเครดิตสำหรับออเดอร์นี้แล้ว');
          }

          tx.set(creditRef, {
            uid,
            amount: -holdAmount,
            timestamp: FieldValue.serverTimestamp(),
            type: 'order_pay_at_destination_hold',
            orderId,
            source: 'rider_accept_order',
            creditedByCloudFunction: true,
          });
        }

        tx.update(orderRef, {
          status: 'accepted',
          driverId: uid,
          acceptedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      });

      return {
        success: true,
        orderId,
        holdAmount,
      };
    },
  );

  return { acceptRiderOrder };
}

module.exports = {
  init,
  registerHandlers,
};
