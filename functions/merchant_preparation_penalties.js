const MERCHANT_SECURITY_DEPOSIT_AMOUNT = 1000;

let db;
let FieldValue;
let onSchedule;
let logger;
let DEFAULT_REGION;
let admin;
let syncMerchantWallet;

function init(deps) {
  db = deps.db;
  FieldValue = deps.FieldValue;
  onSchedule = deps.onSchedule;
  logger = deps.logger;
  DEFAULT_REGION = deps.DEFAULT_REGION;
  admin = deps.admin;
  syncMerchantWallet = deps.syncMerchantWallet;
}

function readMoney(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function resolveSecurityDepositAmount(userData) {
  const user = userData && typeof userData === 'object' ? userData : {};
  const explicit = readMoney(user.merchantSecurityDepositAmount);
  if (explicit > 0) {
    return explicit;
  }
  if (user.merchantSecurityDepositPaid === true) {
    return MERCHANT_SECURITY_DEPOSIT_AMOUNT;
  }
  return 0;
}

function calculatePenalty(overtimeMinutes) {
  return Math.max(0, Math.ceil(Number(overtimeMinutes || 0)));
}

function resolveMerchantUid(order) {
  return String(order?.shopOwnerId || order?.shopId || '').trim();
}

async function sendShopNotification(fcmToken, title, body, orderId) {
  const token = String(fcmToken || '').trim();
  if (!token) {
    return;
  }

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: {
        type: 'order_preparation_penalty',
        orderId: String(orderId || ''),
      },
    });
  } catch (error) {
    logger.warn('sendShopNotification failed', {
      orderId,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

async function chargePreparationPenaltyInTransaction(tx, {
  merchantUid,
  orderId,
  delta,
}) {
  if (delta <= 0) {
    return {
      totalCharged: 0,
      fromGeneral: 0,
      fromDeposit: 0,
      uncollected: 0,
    };
  }

  const userRef = db.collection('users').doc(merchantUid);
  const userSnap = await tx.get(userRef);
  const userData = userSnap.exists ? userSnap.data() || {} : {};

  const creditsQuery = db.collection('credits').where('uid', '==', merchantUid);
  const creditsSnap = await tx.get(creditsQuery);
  let totalCredit = 0;
  for (const doc of creditsSnap.docs) {
    totalCredit += readMoney(doc.data()?.amount);
  }

  const depositAmount = resolveSecurityDepositAmount(userData);
  const generalCredit = Math.max(0, totalCredit - depositAmount);

  let remaining = delta;
  const fromGeneral = Math.min(generalCredit, remaining);
  remaining -= fromGeneral;
  const depositAvailableInCredits = Math.max(0, totalCredit - fromGeneral);
  const fromDeposit = Math.min(depositAmount, remaining, depositAvailableInCredits);
  remaining -= fromDeposit;

  const totalCharged = fromGeneral + fromDeposit;
  const now = FieldValue.serverTimestamp();

  if (fromGeneral > 0) {
    const creditId = `prep_penalty_${orderId}_general_${fromGeneral}_${Date.now()}`;
    tx.set(db.collection('credits').doc(creditId), {
      uid: merchantUid,
      amount: -fromGeneral,
      timestamp: now,
      type: 'merchant_preparation_penalty',
      penaltySource: 'general_credit',
      orderId,
      creditedByCloudFunction: true,
      status: 'posted',
    });
  }

  if (fromDeposit > 0) {
    const creditId = `prep_penalty_${orderId}_deposit_${fromDeposit}_${Date.now()}`;
    tx.set(db.collection('credits').doc(creditId), {
      uid: merchantUid,
      amount: -fromDeposit,
      timestamp: now,
      type: 'merchant_preparation_penalty',
      penaltySource: 'security_deposit',
      orderId,
      creditedByCloudFunction: true,
      status: 'posted',
    });

    const newDeposit = Math.max(0, depositAmount - fromDeposit);
    tx.set(
      userRef,
      {
        merchantSecurityDepositAmount: newDeposit,
        merchantSecurityDepositPaid: newDeposit > 0,
        updatedAt: now,
      },
      { merge: true },
    );
  }

  return {
    totalCharged,
    fromGeneral,
    fromDeposit,
    uncollected: remaining,
  };
}

async function updateOrderPenaltyWithCharge(orderRef, order, orderId, penalty, now) {
  const merchantUid = resolveMerchantUid(order);
  const previousPenalty = readMoney(order.penalty);
  const penaltyCharged = readMoney(order.penaltyCharged);
  const delta = penalty - penaltyCharged;

  const orderUpdates = {
    penalty,
    penaltyUpdatedAt: now,
  };

  if (delta <= 0) {
    if (penalty !== previousPenalty) {
      await orderRef.update(orderUpdates);
    }
    if (merchantUid) {
      await resyncMerchantPenaltyBlock(merchantUid);
    }
    return { charged: 0, penalty, delta: 0 };
  }

  if (!merchantUid) {
    logger.warn('preparation penalty skipped — missing merchant uid', { orderId, penalty, delta });
    await orderRef.set(
      {
        ...orderUpdates,
        penaltyUncollected: delta,
      },
      { merge: true },
    );
    return { charged: 0, penalty, delta, uncollected: delta };
  }

  const charge = await db.runTransaction(async (tx) => {
    const freshOrderSnap = await tx.get(orderRef);
    if (!freshOrderSnap.exists) {
      return null;
    }
    const freshOrder = freshOrderSnap.data() || {};
    const freshPenaltyCharged = readMoney(freshOrder.penaltyCharged);
    const freshDelta = penalty - freshPenaltyCharged;
    if (freshDelta <= 0) {
      tx.set(orderRef, orderUpdates, { merge: true });
      return {
        totalCharged: 0,
        fromGeneral: 0,
        fromDeposit: 0,
        uncollected: 0,
      };
    }

    const result = await chargePreparationPenaltyInTransaction(tx, {
      merchantUid,
      orderId,
      delta: freshDelta,
    });

    tx.set(
      orderRef,
      {
        ...orderUpdates,
        penaltyCharged: freshPenaltyCharged + result.totalCharged,
        penaltyUncollected: result.uncollected,
        penaltyLastCharge: {
          amount: result.totalCharged,
          fromGeneral: result.fromGeneral,
          fromDeposit: result.fromDeposit,
          chargedAt: now,
        },
      },
      { merge: true },
    );

    return result;
  });

  if (!charge) {
    return { charged: 0, penalty, delta: 0 };
  }

  if (charge.totalCharged > 0 && typeof syncMerchantWallet === 'function') {
    try {
      await syncMerchantWallet(merchantUid);
    } catch (error) {
      logger.error('syncMerchantWallet after preparation penalty failed', {
        merchantUid,
        orderId,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  try {
    await resyncMerchantPenaltyBlock(merchantUid);
  } catch (error) {
    logger.error('resyncMerchantPenaltyBlock failed', {
      merchantUid,
      orderId,
      message: error instanceof Error ? error.message : String(error),
    });
  }

  return {
    charged: charge.totalCharged,
    penalty,
    delta,
    fromGeneral: charge.fromGeneral,
    fromDeposit: charge.fromDeposit,
    uncollected: charge.uncollected,
  };
}

async function sumMerchantPenaltyUncollected(merchantUid) {
  const trimmedUid = String(merchantUid || '').trim();
  if (!trimmedUid) {
    return 0;
  }

  const seen = new Set();
  let total = 0;

  for (const field of ['shopId', 'shopOwnerId']) {
    const snapshot = await db
      .collection('orders')
      .where(field, '==', trimmedUid)
      .where('penaltyUncollected', '>', 0)
      .get();

    for (const doc of snapshot.docs) {
      if (seen.has(doc.id)) {
        continue;
      }
      seen.add(doc.id);
      total += readMoney(doc.data()?.penaltyUncollected);
    }
  }

  return Math.round(total * 100) / 100;
}

async function resyncMerchantPenaltyBlock(merchantUid) {
  const trimmedUid = String(merchantUid || '').trim();
  if (!trimmedUid) {
    return { blocked: false, totalUncollected: 0 };
  }

  const totalUncollected = await sumMerchantPenaltyUncollected(trimmedUid);
  const blocked = totalUncollected > 0;
  const now = FieldValue.serverTimestamp();
  const userRef = db.collection('users').doc(trimmedUid);
  const shopOpsRef = db.collection('shop_operations').doc(trimmedUid);
  const userSnap = await userRef.get();
  const wasBlocked = userSnap.exists && userSnap.data()?.merchantPenaltyBlocked === true;

  await userRef.set(
    {
      merchantPenaltyBlocked: blocked,
      merchantPenaltyUncollectedTotal: totalUncollected,
      merchantPenaltyBlockedAt: blocked ? now : null,
      updatedAt: now,
    },
    { merge: true },
  );

  await shopOpsRef.set(
    {
      acceptingOrders: !blocked,
      penaltyBlocked: blocked,
      penaltyBlockReason: blocked
        ? `มีค่าปรับค้างชำระ ${totalUncollected.toFixed(0)} บาท — กรุณาเติมเครดิตหรือเงินประกัน`
        : null,
      updatedAt: now,
    },
    { merge: true },
  );

  if (blocked && !wasBlocked) {
    await db.collection('app_notifications').add({
      targetApp: 'van1',
      recipientUid: trimmedUid,
      title: 'ร้านถูกระงับรับออเดอร์ชั่วคราว',
      body: `มีค่าปรับเตรียมออเดอร์ค้างชำระ ${totalUncollected.toFixed(0)} บาท กรุณาเติมเงินในกระเป๋า`,
      action: 'merchant_penalty_blocked',
      sourceApp: 'van2_cloud_function',
      read: false,
      isRead: false,
      createdAt: now,
    });
  }

  if (!blocked && wasBlocked) {
    await db.collection('app_notifications').add({
      targetApp: 'van1',
      recipientUid: trimmedUid,
      title: 'ปลดระงับรับออเดอร์แล้ว',
      body: 'ชำระค่าปรับครบแล้ว — ร้านสามารถรับออเดอร์ได้ตามปกติ',
      action: 'merchant_penalty_unblocked',
      sourceApp: 'van2_cloud_function',
      read: false,
      isRead: false,
      createdAt: now,
    });
  }

  return { blocked, totalUncollected };
}

async function processPreparingOrdersRun() {
  const now = admin.firestore.Timestamp.now();
  const ordersSnapshot = await db.collection('orders').where('status', '==', 'preparing').get();

  let processed = 0;
  let chargedOrders = 0;
  let totalCharged = 0;

  for (const doc of ordersSnapshot.docs) {
    const order = doc.data() || {};
    const orderId = doc.id;
    processed += 1;

    if (!order.preparingStartTime) {
      continue;
    }

    const preparingStart = order.preparingStartTime.toDate();
    const elapsedMinutes = (now.toDate().getTime() - preparingStart.getTime()) / 1000 / 60;
    const preparingDurationMs = Number(order.preparingDuration || 600000);
    const preparingDurationMinutes = Math.max(1, preparingDurationMs / 1000 / 60);
    const firstWarningMinutes = Number(
      order.notifications?.firstWarning?.timeInMinutes || preparingDurationMinutes * 0.5,
    );
    const secondWarningMinutes = Number(
      order.notifications?.secondWarning?.timeInMinutes || preparingDurationMinutes * 0.75,
    );
    const finalWarningMinutes = Number(
      order.notifications?.finalWarning?.timeInMinutes || preparingDurationMinutes,
    );

    const updates = [];

    if (elapsedMinutes >= firstWarningMinutes && !order.notifications?.firstWarning?.sent) {
      const remainingMinutes = Math.max(0, preparingDurationMinutes - elapsedMinutes);
      updates.push(
        sendShopNotification(
          order.shopFCMToken,
          'แจ้งเตือนเวลาเตรียมออเดอร์',
          `ออเดอร์ #${orderId.substring(0, 8)} ใช้เวลาไป ${elapsedMinutes.toFixed(1)} นาทีแล้ว เหลืออีก ${remainingMinutes.toFixed(1)} นาที`,
          orderId,
        ),
        doc.ref.update({
          'notifications.firstWarning.sent': true,
          'notifications.firstWarning.sentAt': now,
        }),
      );
    }

    if (elapsedMinutes >= secondWarningMinutes && !order.notifications?.secondWarning?.sent) {
      const remainingMinutes = Math.max(0, preparingDurationMinutes - elapsedMinutes);
      updates.push(
        sendShopNotification(
          order.shopFCMToken,
          'แจ้งเตือนเวลาเตรียมออเดอร์ (เร่งด่วน)',
          `ออเดอร์ #${orderId.substring(0, 8)} ใช้เวลาไป ${elapsedMinutes.toFixed(1)} นาทีแล้ว เหลืออีก ${remainingMinutes.toFixed(1)} นาที`,
          orderId,
        ),
        doc.ref.update({
          'notifications.secondWarning.sent': true,
          'notifications.secondWarning.sentAt': now,
        }),
      );
    }

    if (elapsedMinutes > preparingDurationMinutes) {
      const overtimeMinutes = elapsedMinutes - preparingDurationMinutes;
      const penalty = calculatePenalty(overtimeMinutes);

      if (elapsedMinutes >= finalWarningMinutes && !order.notifications?.finalWarning?.sent) {
        updates.push(
          sendShopNotification(
            order.shopFCMToken,
            'เกินเวลาเตรียมออเดอร์!',
            `ออเดอร์ #${orderId.substring(0, 8)} เกินเวลา ${overtimeMinutes.toFixed(1)} นาที มีค่าปรับ ${penalty} บาท`,
            orderId,
          ),
          doc.ref.update({
            'notifications.finalWarning.sent': true,
            'notifications.finalWarning.sentAt': now,
          }),
        );
      }

      const chargeResult = await updateOrderPenaltyWithCharge(doc.ref, order, orderId, penalty, now);
      if (chargeResult.charged > 0) {
        chargedOrders += 1;
        totalCharged += chargeResult.charged;
      }
    }

    if (updates.length > 0) {
      await Promise.allSettled(updates);
    }
  }

  logger.info('checkPreparingOrders done', {
    processed,
    chargedOrders,
    totalCharged,
  });

  return { processed, chargedOrders, totalCharged };
}

function registerHandlers() {
  const checkPreparingOrders = onSchedule(
    {
      region: DEFAULT_REGION,
      schedule: 'every 1 minutes',
      timeZone: 'Asia/Bangkok',
    },
    async () => {
      try {
        await processPreparingOrdersRun();
      } catch (error) {
        logger.error('checkPreparingOrders failed', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
    },
  );

  return { checkPreparingOrders };
}

module.exports = {
  init,
  registerHandlers,
  calculatePenalty,
  chargePreparationPenaltyInTransaction,
  processPreparingOrdersRun,
};
