const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { assertVan4Admin, assertSuperAdmin, assertAdminBranchAccess, resolveMerchantBranchId } = require('./social/admin_guard');
const { syncMerchantWallet } = require('./merchant_wallet');

const CREDITS_COLLECTION = 'credits';
const MERCHANT_WALLETS_COLLECTION = 'merchant_wallets';
const WITHDRAW_REQUESTS_COLLECTION = 'withdraw_requests';
const ORDERS_COLLECTION = 'orders';
const RIDERS_COLLECTION = 'riders';
const USERS_COLLECTION = 'users';
const APP_NOTIFICATIONS_COLLECTION = 'app_notifications';
const CREDIT_ADMIN_ACTIONS_COLLECTION = 'credit_admin_actions';

const ACTOR_MERCHANT = 'merchant';
const ACTOR_RIDER = 'rider';
const MAX_ADJUST_AMOUNT = 50000;
const DEFAULT_LEDGER_LIMIT = 50;

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

function readMoney(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function roundMoney(value) {
  return Math.round(readMoney(value) * 100) / 100;
}

function normalizeActorType(value) {
  const actorType = readString(value).toLowerCase();
  if (actorType === ACTOR_MERCHANT || actorType === ACTOR_RIDER) {
    return actorType;
  }
  return '';
}

async function sumCreditsForUid(uid) {
  const snapshot = await db.collection(CREDITS_COLLECTION).where('uid', '==', uid).get();
  let total = 0;
  for (const doc of snapshot.docs) {
    total += readMoney(doc.data()?.amount);
  }
  return roundMoney(total);
}

async function loadPendingWithdrawTotal(uid) {
  const snapshot = await db
    .collection(WITHDRAW_REQUESTS_COLLECTION)
    .where('uid', '==', uid)
    .where('status', '==', 'pending_admin')
    .get();
  let total = 0;
  for (const doc of snapshot.docs) {
    total += readMoney(doc.data()?.amount);
  }
  return roundMoney(total);
}

async function loadPendingReleaseOrders(uid, actorType) {
  const field =
    actorType === ACTOR_MERCHANT ? 'shopCreditReleaseStatus' : 'riderCreditReleaseStatus';
  const ownerField = actorType === ACTOR_MERCHANT ? 'shopOwnerId' : 'driverId';
  const statuses = ['scheduled', 'held'];
  const orders = [];

  for (const status of statuses) {
    const snapshot = await db
      .collection(ORDERS_COLLECTION)
      .where(ownerField, '==', uid)
      .where(field, '==', status)
      .limit(25)
      .get();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const settlementKey =
        actorType === ACTOR_MERCHANT ? 'shopCreditRelease' : 'riderCreditRelease';
      const release = data.settlement?.[settlementKey] || {};
      orders.push({
        orderId: doc.id,
        orderCode: readString(data.orderCode) || doc.id,
        status,
        amount: roundMoney(release.amount),
        scheduledReleaseAt: release.scheduledReleaseAt || null,
        holdReason: readString(release.holdReason) || null,
      });
    }
  }

  return orders.slice(0, 50);
}

function creditEntryToLedgerItem(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    uid: readString(data.uid),
    amount: roundMoney(data.amount),
    type: readString(data.type) || 'unknown',
    reason: readString(data.reason) || null,
    note: readString(data.note) || null,
    orderId: readString(data.orderId) || null,
    adminUid: readString(data.adminUid) || null,
    source: readString(data.source) || null,
    timestamp: data.timestamp || null,
  };
}

async function countOrdersByStatus(field, status) {
  try {
    const aggregate = await db
      .collection(ORDERS_COLLECTION)
      .where(field, '==', status)
      .count()
      .get();
    return aggregate.data().count || 0;
  } catch (_) {
    const snapshot = await db
      .collection(ORDERS_COLLECTION)
      .where(field, '==', status)
      .limit(500)
      .get();
    return snapshot.size;
  }
}

async function sumRiderCredits() {
  const ridersSnap = await db.collection(RIDERS_COLLECTION).limit(2000).get();
  const riderUids = ridersSnap.docs.map((doc) => doc.id);
  let total = 0;
  const batchSize = 10;

  for (let i = 0; i < riderUids.length; i += batchSize) {
    const batch = riderUids.slice(i, i + batchSize);
    if (batch.length === 0) {
      continue;
    }
    const creditsSnap = await db
      .collection(CREDITS_COLLECTION)
      .where('uid', 'in', batch)
      .get();
    for (const doc of creditsSnap.docs) {
      total += readMoney(doc.data()?.amount);
    }
  }

  return {
    riderCount: riderUids.length,
    riderCreditTotal: roundMoney(total),
  };
}

function registerHandlers() {
  const adminGetCreditOverview = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      await assertSuperAdmin(request);

      const walletsSnap = await db.collection(MERCHANT_WALLETS_COLLECTION).limit(5000).get();
      let merchantCreditTotal = 0;
      let merchantWithdrawableTotal = 0;
      let merchantLockedTotal = 0;

      for (const doc of walletsSnap.docs) {
        const data = doc.data() || {};
        merchantCreditTotal += readMoney(data.totalCredit);
        merchantWithdrawableTotal += readMoney(data.withdrawableCredit);
        merchantLockedTotal += readMoney(data.lockedCredit);
      }

      const riderStats = await sumRiderCredits();
      const [
        shopScheduledCount,
        shopHeldCount,
        riderScheduledCount,
        riderHeldCount,
      ] = await Promise.all([
        countOrdersByStatus('shopCreditReleaseStatus', 'scheduled'),
        countOrdersByStatus('shopCreditReleaseStatus', 'held'),
        countOrdersByStatus('riderCreditReleaseStatus', 'scheduled'),
        countOrdersByStatus('riderCreditReleaseStatus', 'held'),
      ]);

      return {
        merchant: {
          walletCount: walletsSnap.size,
          creditTotal: roundMoney(merchantCreditTotal),
          withdrawableTotal: roundMoney(merchantWithdrawableTotal),
          lockedTotal: roundMoney(merchantLockedTotal),
        },
        rider: {
          riderCount: riderStats.riderCount,
          creditTotal: riderStats.riderCreditTotal,
        },
        pendingReleases: {
          shopScheduledCount,
          shopHeldCount,
          riderScheduledCount,
          riderHeldCount,
        },
      };
    },
  );

  const adminGetActorWallet = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      await assertVan4Admin(request);

      const uid = readString(request.data?.uid);
      const actorType = normalizeActorType(request.data?.actorType);
      if (!uid) {
        throw new HttpsError('invalid-argument', 'ต้องระบุ uid');
      }
      if (!actorType) {
        throw new HttpsError('invalid-argument', 'actorType ต้องเป็น merchant หรือ rider');
      }

      const [creditTotal, pendingWithdrawTotal, pendingReleases] = await Promise.all([
        sumCreditsForUid(uid),
        loadPendingWithdrawTotal(uid),
        loadPendingReleaseOrders(uid, actorType),
      ]);

      let displayName = uid;
      let merchantWallet = null;

      if (actorType === ACTOR_MERCHANT) {
        const [userDoc, walletDoc] = await Promise.all([
          db.collection(USERS_COLLECTION).doc(uid).get(),
          db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid).get(),
        ]);
        if (userDoc.exists) {
          const userData = userDoc.data() || {};
          displayName =
            readString(userData.displayName || userData.name || userData.shopName) || displayName;
        }
        if (walletDoc.exists) {
          const data = walletDoc.data() || {};
          merchantWallet = {
            totalCredit: roundMoney(data.totalCredit),
            withdrawableCredit: roundMoney(data.withdrawableCredit),
            lockedCredit: roundMoney(data.lockedCredit),
            omiseWithdrawableCredit: roundMoney(data.omiseWithdrawableCredit),
            omiseLockedCredit: roundMoney(data.omiseLockedCredit),
            omisePendingCredit: roundMoney(data.omisePendingCredit),
            canWithdraw: data.canWithdraw === true,
            contractStatus: readString(data.contractStatus) || 'active',
            isContractCancelled: data.isContractCancelled === true,
          };
        }
      } else {
        const riderDoc = await db.collection(RIDERS_COLLECTION).doc(uid).get();
        if (riderDoc.exists) {
          const data = riderDoc.data() || {};
          displayName = readString(data.displayName || data.name) || displayName;
        }
      }

      return {
        uid,
        actorType,
        displayName,
        creditTotal,
        availableBalance: roundMoney(Math.max(0, creditTotal)),
        pendingWithdrawTotal,
        merchantWallet,
        pendingReleases,
      };
    },
  );

  const adminListCreditLedger = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      await assertVan4Admin(request);

      const uid = readString(request.data?.uid);
      if (!uid) {
        throw new HttpsError('invalid-argument', 'ต้องระบุ uid');
      }

      const limitRaw = Number.parseInt(String(request.data?.limit ?? DEFAULT_LEDGER_LIMIT), 10);
      const limit = Number.isFinite(limitRaw)
        ? Math.min(Math.max(limitRaw, 1), 100)
        : DEFAULT_LEDGER_LIMIT;
      const cursorId = readString(request.data?.cursorId);

      let query = db
        .collection(CREDITS_COLLECTION)
        .where('uid', '==', uid)
        .orderBy('timestamp', 'desc')
        .limit(limit);

      if (cursorId) {
        const cursorDoc = await db.collection(CREDITS_COLLECTION).doc(cursorId).get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const snapshot = await query.get();
      const items = snapshot.docs.map(creditEntryToLedgerItem);
      const nextCursorId =
        snapshot.docs.length >= limit ? snapshot.docs[snapshot.docs.length - 1].id : null;

      return {
        uid,
        items,
        nextCursorId,
      };
    },
  );

  const adminAdjustCredit = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      const adminUser = await assertVan4Admin(request);

      const uid = readString(request.data?.uid);
      const actorType = normalizeActorType(request.data?.actorType);
      const amount = roundMoney(request.data?.amount);
      const reason = readString(request.data?.reason);
      const note = readString(request.data?.note);
      const clientToken = readString(request.data?.clientToken);

      if (!uid) {
        throw new HttpsError('invalid-argument', 'ต้องระบุ uid');
      }
      if (!actorType) {
        throw new HttpsError('invalid-argument', 'actorType ต้องเป็น merchant หรือ rider');
      }
      if (!reason) {
        throw new HttpsError('invalid-argument', 'ต้องระบุเหตุผล');
      }
      if (amount === 0) {
        throw new HttpsError('invalid-argument', 'จำนวนเงินต้องไม่เป็น 0');
      }
      if (Math.abs(amount) > MAX_ADJUST_AMOUNT) {
        throw new HttpsError(
          'invalid-argument',
          `ปรับได้สูงสุด ${MAX_ADJUST_AMOUNT} บาทต่อครั้ง`,
        );
      }
      if (!clientToken) {
        throw new HttpsError('invalid-argument', 'ต้องระบุ clientToken');
      }

      const creditId = `admin_adj_${adminUser.uid}_${clientToken}`;
      const creditRef = db.collection(CREDITS_COLLECTION).doc(creditId);
      const auditRef = db.collection(CREDIT_ADMIN_ACTIONS_COLLECTION).doc(creditId);

      const existing = await creditRef.get();
      if (existing.exists) {
        const data = existing.data() || {};
        return {
          success: true,
          duplicate: true,
          creditId,
          amount: roundMoney(data.amount),
          creditTotal: await sumCreditsForUid(uid),
        };
      }

      const beforeBalance = await sumCreditsForUid(uid);
      const afterBalance = roundMoney(beforeBalance + amount);
      if (afterBalance < 0) {
        throw new HttpsError(
          'failed-precondition',
          `ยอดหลังปรับจะติดลบ (${afterBalance}) — ยกเลิกหรือปรับจำนวน`,
        );
      }

      const now = FieldValue.serverTimestamp();
      const creditPayload = {
        uid,
        amount,
        type: 'admin_adjustment',
        reason,
        note: note || null,
        adminUid: adminUser.uid,
        adminEmail: adminUser.email,
        actorType,
        creditedByCloudFunction: true,
        source: 'van4_admin',
        timestamp: now,
      };

      await db.runTransaction(async (tx) => {
        tx.set(creditRef, creditPayload);
        tx.set(auditRef, {
          ...creditPayload,
          creditId,
          beforeBalance,
          afterBalance,
          createdAt: now,
        });
      });

      let merchantWallet = null;
      if (actorType === ACTOR_MERCHANT) {
        const walletFields = await syncMerchantWallet(uid);
        merchantWallet = walletFields;
      }

      const targetApp = actorType === ACTOR_MERCHANT ? 'van1' : 'van3';
      const sign = amount >= 0 ? '+' : '';
      await db.collection(APP_NOTIFICATIONS_COLLECTION).add({
        targetApp,
        recipientUid: uid,
        title: 'แอดมินปรับเครดิต',
        body: `${sign}${Math.round(amount)} บาท — ${reason}`,
        action: 'credit_adjusted',
        sourceApp: 'van4_admin',
        senderId: adminUser.uid,
        read: false,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        duplicate: false,
        creditId,
        uid,
        actorType,
        amount,
        beforeBalance,
        afterBalance,
        creditTotal: afterBalance,
        merchantWallet,
      };
    },
  );

  return {
    adminGetCreditOverview,
    adminGetActorWallet,
    adminListCreditLedger,
    adminAdjustCredit,
  };
}

module.exports = {
  init,
  registerHandlers,
};
