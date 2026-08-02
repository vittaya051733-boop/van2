const { onCall } = require('firebase-functions/v2/https');

let db;
let FieldValue;
let HttpsError;
let DEFAULT_REGION;

const SHOP_DECISION_THRESHOLD_MS = 15 * 60 * 1000;
const CUSTOMER_EXTRA_WAIT_MS = 15 * 60 * 1000;
const SCHEDULED_TRAVEL_LEAD_MS = 15 * 60 * 1000;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  HttpsError = deps.HttpsError;
  DEFAULT_REGION = deps.DEFAULT_REGION;
}

function readString(value) {
  return String(value ?? '').trim();
}

function readTimestamp(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  return null;
}

function isTerminalStatus(status) {
  const normalized = readString(status).toLowerCase();
  return (
    normalized === 'cancelled' ||
    normalized === 'refund' ||
    normalized === 'refunded' ||
    normalized === 'completed' ||
    normalized === 'delivered'
  );
}

function isCashOnDelivery(data) {
  const paymentMethod = readString(data.paymentMethod).toLowerCase();
  const paymentStatus = readString(data.paymentStatus).toLowerCase();
  return paymentMethod === 'cash_on_delivery' || paymentStatus === 'cash_on_delivery';
}

function canRequestRefund(data) {
  if (isCashOnDelivery(data)) {
    return false;
  }
  return readString(data.paymentStatus).toLowerCase() === 'verified';
}

function isTravelOrder(data) {
  const orderType = readString(data.orderType);
  const serviceType = readString(data.serviceType);
  return orderType === 'travel_passenger' || serviceType === 'travel_passenger';
}

function isScheduledTravelOrder(data) {
  if (!isTravelOrder(data)) {
    return false;
  }
  if (data.isImmediate === false) {
    return true;
  }
  const travelRequest = data.travelRequest;
  return Boolean(travelRequest && travelRequest.isImmediate === false);
}

function readScheduledAt(data) {
  return (
    readTimestamp(data.scheduledAt) ||
    (data.travelRequest && readTimestamp(data.travelRequest.scheduledAt)) ||
    null
  );
}

function isCustomerWaiting(data, nowMs = Date.now()) {
  const waitUntil = readTimestamp(data.customerWaitUntil);
  return Boolean(waitUntil && waitUntil.getTime() > nowMs);
}

function shopHasAccepted(data) {
  const status = readString(data.status);
  return (
    data.preparingStartTime != null ||
    status === 'preparing' ||
    status === 'ready' ||
    status === 'delivering' ||
    status === 'delivered'
  );
}

function shopRejected(data) {
  const cancelReason = readString(data.cancelReason);
  return (
    readString(data.shopDecisionStatus) === 'rejected' ||
    data.shopRejectedAt != null ||
    cancelReason === 'shop_rejected_waiting_customer_decision' ||
    cancelReason === 'shop_rejected_order'
  );
}

function isShopStaleEligible(data, nowMs = Date.now()) {
  if (shopHasAccepted(data) || isTerminalStatus(data.status)) {
    return false;
  }
  if (shopRejected(data)) {
    return true;
  }
  const waitUntil = readTimestamp(data.customerShopWaitUntil);
  if (waitUntil && waitUntil.getTime() > nowMs) {
    return true;
  }
  if (readString(data.status) !== 'accepted') {
    return false;
  }
  const acceptedAt = readTimestamp(data.acceptedAt);
  if (!acceptedAt) {
    return false;
  }
  return nowMs - acceptedAt.getTime() >= SHOP_DECISION_THRESHOLD_MS;
}

function hasUnmatchedRiderState(data) {
  const status = readString(data.status);
  const driverId = readString(data.driverId);
  if (status === 'awaiting_rider' && !driverId) {
    return true;
  }
  return status === 'pending' && Boolean(driverId);
}

function riderWaitStartedAt(data) {
  return (
    readTimestamp(data.customerWaitRequestedAt) ||
    readTimestamp(data.reassignedAt) ||
    readTimestamp(data.assignedRiderAt) ||
    readTimestamp(data.customerConfirmedAt) ||
    readTimestamp(data.createdAt)
  );
}

function shouldShowNoRiderActions(data, nowMs = Date.now()) {
  if (isTerminalStatus(data.status) || readTimestamp(data.acceptedAt)) {
    return false;
  }
  if (isCustomerWaiting(data, nowMs)) {
    return true;
  }
  const reassignFailed = readString(data.reassignFailureReason);
  if (reassignFailed) {
    return true;
  }
  if (!hasUnmatchedRiderState(data)) {
    return false;
  }
  if (isScheduledTravelOrder(data)) {
    const scheduledAt = readScheduledAt(data);
    if (!scheduledAt) {
      const waitStartedAt = riderWaitStartedAt(data);
      return Boolean(
        waitStartedAt && nowMs - waitStartedAt.getTime() >= SHOP_DECISION_THRESHOLD_MS,
      );
    }
    return scheduledAt.getTime() - nowMs <= SCHEDULED_TRAVEL_LEAD_MS;
  }
  const waitStartedAt = riderWaitStartedAt(data);
  if (!waitStartedAt) {
    return false;
  }
  return nowMs - waitStartedAt.getTime() >= SHOP_DECISION_THRESHOLD_MS;
}

function assertCustomerOwnsOrder(orderData, uid) {
  const customerId = readString(orderData.customerId);
  if (!customerId || customerId !== uid) {
    throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์จัดการออเดอร์นี้');
  }
}

function sanitizeRefundInfo(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  const refundBankAccountNumber = readString(raw.refundBankAccountNumber);
  const refundAccountName = readString(raw.refundAccountName);
  const refundBankName = readString(raw.refundBankName);
  if (!refundBankAccountNumber || !refundAccountName || !refundBankName) {
    throw new HttpsError('invalid-argument', 'กรุณากรอกข้อมูลบัญชีคืนเงินให้ครบ');
  }
  return {
    refundBankAccountNumber,
    refundAccountName,
    refundBankName,
  };
}

async function customerOrderActionHandler(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
  }

  const uid = request.auth.uid;
  const orderId = readString(request.data?.orderId);
  const action = readString(request.data?.action);
  if (!orderId || !action) {
    throw new HttpsError('invalid-argument', 'ข้อมูลคำขอไม่ครบ');
  }

  const orderRef = db.collection('orders').doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new HttpsError('not-found', 'ไม่พบออเดอร์');
  }

  const orderData = orderSnap.data() || {};
  assertCustomerOwnsOrder(orderData, uid);

  if (isTerminalStatus(orderData.status)) {
    throw new HttpsError('failed-precondition', 'ออเดอร์นี้ปิดแล้ว');
  }

  const nowMs = Date.now();
  let update = {
    updatedAt: FieldValue.serverTimestamp(),
  };

  switch (action) {
    case 'shop_wait_15_min': {
      if (!isShopStaleEligible(orderData, nowMs)) {
        throw new HttpsError('failed-precondition', 'ยังไม่สามารถรอร้านค้าเพิ่มได้');
      }
      update = {
        ...update,
        status: 'accepted',
        customerShopWaitUntil: new Date(nowMs + CUSTOMER_EXTRA_WAIT_MS),
        customerShopWaitRequestedAt: FieldValue.serverTimestamp(),
        customerShopChoice: 'wait_15_min',
        shopDecisionStatus: FieldValue.delete(),
        shopRejectedAt: FieldValue.delete(),
        shopRejectedBy: FieldValue.delete(),
        cancelReason: FieldValue.delete(),
      };
      break;
    }
    case 'shop_cancel': {
      if (!isShopStaleEligible(orderData, nowMs)) {
        throw new HttpsError('failed-precondition', 'ยังไม่สามารถยกเลิกออเดอร์นี้ได้');
      }
      const refundInfo = canRequestRefund(orderData)
        ? sanitizeRefundInfo(request.data?.refundInfo)
        : null;
      if (canRequestRefund(orderData) && !refundInfo) {
        throw new HttpsError('invalid-argument', 'กรุณากรอกข้อมูลบัญชีคืนเงิน');
      }
      update = {
        ...update,
        status: 'cancelled',
        statusLabel: 'ยกเลิกออเดอร์',
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: uid,
        cancelReason: shopRejected(orderData)
          ? 'customer_cancelled_after_shop_rejected'
          : 'customer_cancelled_after_shop_no_response',
        customerShopChoice: 'cancel',
        customerCancelledAt: FieldValue.serverTimestamp(),
      };
      if (refundInfo) {
        Object.assign(update, {
          refundRequested: true,
          refundRequestedAt: FieldValue.serverTimestamp(),
          refundRequestedBy: uid,
          refundStatus: 'requested',
          ...refundInfo,
        });
      }
      break;
    }
    case 'no_rider_wait_15_min': {
      if (!shouldShowNoRiderActions(orderData, nowMs)) {
        throw new HttpsError('failed-precondition', 'ยังไม่สามารถรอไรเดอร์เพิ่มได้');
      }
      update = {
        ...update,
        customerWaitUntil: new Date(nowMs + CUSTOMER_EXTRA_WAIT_MS),
        customerWaitRequestedAt: FieldValue.serverTimestamp(),
        customerNoRiderChoice: 'wait_15_min',
        reassignFailureReason: FieldValue.delete(),
        needsReassign: true,
      };
      break;
    }
    case 'no_rider_cancel': {
      if (!shouldShowNoRiderActions(orderData, nowMs)) {
        throw new HttpsError('failed-precondition', 'ยังไม่สามารถยกเลิกออเดอร์นี้ได้');
      }
      if (canRequestRefund(orderData)) {
        throw new HttpsError(
          'failed-precondition',
          'ออเดอร์นี้ต้องขอคืนเงินแทนการยกเลิก',
        );
      }
      update = {
        ...update,
        status: 'cancelled',
        statusLabel: 'ยกเลิกออเดอร์',
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: uid,
        cancelReason: isScheduledTravelOrder(orderData)
          ? 'scheduled_travel_no_rider_customer_cancelled'
          : 'no_rider_available_customer_cancelled',
        customerNoRiderChoice: 'cancel',
        needsReassign: false,
      };
      break;
    }
    case 'no_rider_refund': {
      if (!shouldShowNoRiderActions(orderData, nowMs)) {
        throw new HttpsError('failed-precondition', 'ยังไม่สามารถขอคืนเงินได้');
      }
      if (!canRequestRefund(orderData)) {
        throw new HttpsError('failed-precondition', 'ออเดอร์นี้ไม่รองรับการขอคืนเงิน');
      }
      const refundInfo = sanitizeRefundInfo(request.data?.refundInfo);
      update = {
        ...update,
        status: 'refund',
        cancelledAt: FieldValue.serverTimestamp(),
        cancelReason: isScheduledTravelOrder(orderData)
          ? 'scheduled_travel_no_rider_refund_requested'
          : 'no_rider_available_refund_requested',
        refundRequested: true,
        refundRequestedAt: FieldValue.serverTimestamp(),
        refundRequestedBy: uid,
        refundStatus: 'requested',
        ...refundInfo,
        customerNoRiderChoice: 'refund',
        needsReassign: false,
      };
      break;
    }
    default:
      throw new HttpsError('invalid-argument', 'คำสั่งไม่รองรับ');
  }

  await orderRef.set(update, { merge: true });
  return { success: true, orderId, action };
}

function registerHandlers() {
  return {
    customerOrderAction: onCall(
      {
        region: DEFAULT_REGION,
        enforceAppCheck: true,
      },
      customerOrderActionHandler,
    ),
  };
}

module.exports = {
  init,
  registerHandlers,
  customerOrderActionHandler,
};
