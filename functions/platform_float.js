const RESERVE_DOC_ID = 'reserve';
const WITHDRAW_HOLD_MS = 24 * 60 * 60 * 1000;
const OMISE_SETTLE_MS = 7 * 24 * 60 * 60 * 1000;

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

function normalizeOrderStatus(status) {
  return String(status || '').trim().toLowerCase();
}

function createPlatformFloatHandlers(deps) {
  const {
    db,
    FieldValue,
    onDocumentUpdated,
    onSchedule,
    logger,
    DEFAULT_REGION,
  } = deps;

  async function ensureReserveDoc(tx) {
    const reserveRef = db.collection('platform_config').doc(RESERVE_DOC_ID);
    const reserveDoc = await tx.get(reserveRef);
    if (!reserveDoc.exists) {
      tx.set(
        reserveRef,
        {
          balance: 500000,
          outstandingFloat: 0,
          minBalanceAlert: 100000,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return reserveRef;
  }

  const syncFloatAdvanceOnOrderDelivered = onDocumentUpdated(
    {
      region: DEFAULT_REGION,
      document: 'orders/{orderId}',
    },
    async (event) => {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      if (!before || !after) {
        return;
      }

      const beforeStatus = normalizeOrderStatus(before.status);
      const afterStatus = normalizeOrderStatus(after.status);
      if (beforeStatus === afterStatus || afterStatus !== 'delivered') {
        return;
      }
      if (after.floatAdvanceCreated === true) {
        return;
      }

      const settlement = after.settlement?.shopPayout;
      if (!settlement || settlement.paymentProvider !== 'omise') {
        return;
      }

      const shopOwnerId = String(after.shopOwnerId || after.shopId || '').trim();
      const payoutAmount = readMoney(settlement.amount);
      if (!shopOwnerId || payoutAmount <= 0) {
        return;
      }

      const orderId = event.params.orderId;
      const now = new Date();
      const availableForWithdrawAt = new Date(now.getTime() + WITHDRAW_HOLD_MS);
      const omiseExpectedSettleAt = new Date(now.getTime() + OMISE_SETTLE_MS);
      const advanceRef = db.collection('float_advances').doc();
      const walletRef = db.collection('merchant_wallets').doc(shopOwnerId);
      const orderRef = event.data.after.ref;

      await db.runTransaction(async (tx) => {
        const reserveRef = await ensureReserveDoc(tx);
        const reserveDoc = await tx.get(reserveRef);
        const reserve = reserveDoc.data() || {};
        const reserveBalance = readMoney(reserve.balance);
        const outstandingFloat = readMoney(reserve.outstandingFloat);
        const minBalanceAlert = readMoney(reserve.minBalanceAlert) || 100000;

        if (reserveBalance - outstandingFloat - payoutAmount < minBalanceAlert) {
          logger.warn('platform float below alert threshold', {
            orderId,
            shopOwnerId,
            payoutAmount,
            reserveBalance,
            outstandingFloat,
          });
        }

        tx.set(advanceRef, {
          advanceId: advanceRef.id,
          orderId,
          shopOwnerId,
          amount: payoutAmount,
          status: 'open',
          fundingSource: 'platform_float',
          paymentProvider: 'omise',
          omiseChargeId: settlement.omiseChargeId || null,
          paymentSessionId: settlement.paymentSessionId || null,
          orderCompletedAt: FieldValue.serverTimestamp(),
          availableForWithdrawAt,
          omiseExpectedSettleAt,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        tx.set(
          reserveRef,
          {
            outstandingFloat: outstandingFloat + payoutAmount,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        tx.set(
          walletRef,
          {
            uid: shopOwnerId,
            omiseLockedCredit: FieldValue.increment(payoutAmount),
            omisePendingCredit: FieldValue.increment(payoutAmount),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        tx.set(
          orderRef,
          {
            floatAdvanceCreated: true,
            floatAdvanceId: advanceRef.id,
            settlement: {
              shopPayout: {
                ...settlement,
                status: 'pending',
                floatAdvanceId: advanceRef.id,
                orderCompletedAt: FieldValue.serverTimestamp(),
                availableForWithdrawAt,
                omiseExpectedSettleAt,
              },
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });

      logger.info('float advance created', { orderId, shopOwnerId, payoutAmount });
    },
  );

  const promoteMerchantPayoutsScheduled = onSchedule(
    {
      region: DEFAULT_REGION,
      schedule: 'every 15 minutes',
      timeZone: 'Asia/Bangkok',
    },
    async () => {
      const now = new Date();
      const snapshot = await db
        .collection('float_advances')
        .where('status', '==', 'open')
        .limit(200)
        .get();

      const batch = db.batch();
      let promoted = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const availableAt = data.availableForWithdrawAt?.toDate?.();
        if (!availableAt || availableAt.getTime() > now.getTime()) {
          continue;
        }

        const shopOwnerId = String(data.shopOwnerId || '').trim();
        const amount = readMoney(data.amount);
        if (!shopOwnerId || amount <= 0) {
          continue;
        }

        batch.set(
          doc.ref,
          {
            status: 'available',
            promotedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        batch.set(
          db.collection('merchant_wallets').doc(shopOwnerId),
          {
            omiseLockedCredit: FieldValue.increment(-amount),
            omisePendingCredit: FieldValue.increment(-amount),
            omiseWithdrawableCredit: FieldValue.increment(amount),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        if (data.orderId) {
          batch.set(
            db.collection('orders').doc(String(data.orderId)),
            {
              settlement: {
                shopPayout: {
                  status: 'available',
                  availableForWithdrawAt: data.availableForWithdrawAt || null,
                },
              },
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }

        promoted += 1;
      }

      if (promoted > 0) {
        await batch.commit();
      }

      logger.info('promoteMerchantPayoutsScheduled done', { promoted });
    },
  );

  const reconcileOmiseSettleScheduled = onSchedule(
    {
      region: DEFAULT_REGION,
      schedule: 'every 6 hours',
      timeZone: 'Asia/Bangkok',
    },
    async () => {
      const now = new Date();
      const openSnapshot = await db
        .collection('float_advances')
        .where('status', '==', 'open')
        .limit(200)
        .get();
      const availableSnapshot = await db
        .collection('float_advances')
        .where('status', '==', 'available')
        .limit(200)
        .get();
      const snapshot = [...openSnapshot.docs, ...availableSnapshot.docs];

      const batch = db.batch();
      let settled = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        const expectedSettleAt = data.omiseExpectedSettleAt?.toDate?.();
        if (!expectedSettleAt || expectedSettleAt.getTime() > now.getTime()) {
          continue;
        }

        const amount = readMoney(data.amount);
        batch.set(
          doc.ref,
          {
            status: 'settled',
            settledAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        batch.set(
          db.collection('platform_config').doc(RESERVE_DOC_ID),
          {
            outstandingFloat: FieldValue.increment(-amount),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        settled += 1;
      }

      if (settled > 0) {
        await batch.commit();
      }

      logger.info('reconcileOmiseSettleScheduled done', { settled });
    },
  );

  return {
    syncFloatAdvanceOnOrderDelivered,
    promoteMerchantPayoutsScheduled,
    reconcileOmiseSettleScheduled,
  };
}

module.exports = {
  createPlatformFloatHandlers,
};
