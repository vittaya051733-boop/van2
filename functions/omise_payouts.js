const OMISE_API_BASE = 'https://api.omise.co';

const MIN_WITHDRAW_BAHT = 30;
const ACTIVE_WITHDRAW_STATUSES = ['pending', 'processing', 'submitted'];
const STALE_WITHDRAW_MS = 15 * 60 * 1000;
const MERCHANT_WALLETS_COLLECTION = 'merchant_wallets';

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

function roundMoney(value) {
  return Math.round(readMoney(value) * 100) / 100;
}

function normalizeOmiseKey(raw) {
  return String(raw || '')
    .trim()
    .replace(/^['"]+|['"]+$/g, '')
    .replace(/\s+/g, '');
}

async function omiseRequest(secretKey, method, path, body) {
  const auth = Buffer.from(`${normalizeOmiseKey(secretKey)}:`).toString('base64');
  const response = await fetch(`${OMISE_API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      payload?.message ||
      payload?.error ||
      `Omise request failed (${response.status})`;
    throw new Error(message);
  }
  return payload;
}

function mapThaiBankToOmiseBrand(bankName) {
  const normalized = String(bankName || '').trim().toLowerCase();
  if (!normalized || normalized === 'อื่นๆ') {
    return null;
  }
  if (normalized.includes('bbl') || normalized.includes('กรุงเทพ')) {
    return 'bbl';
  }
  if (normalized.includes('kbank') || normalized.includes('kasikorn') || normalized.includes('กสิกร')) {
    return 'kbank';
  }
  if (normalized.includes('scb') || normalized.includes('ไทยพาณิชย์')) {
    return 'scb';
  }
  if (normalized.includes('ktb') || normalized.includes('กรุงไทย')) {
    return 'ktb';
  }
  if (normalized.includes('bay') || normalized.includes('กรุงศรี')) {
    return 'bay';
  }
  if (normalized.includes('ttb') || normalized.includes('tmb') || normalized.includes('ธนชาต')) {
    return 'ttb';
  }
  return null;
}

function maskAccountNumber(accountNumber) {
  const digits = String(accountNumber || '').replace(/\D/g, '');
  if (digits.length <= 4) {
    return digits;
  }
  return `••••${digits.slice(-4)}`;
}

function isContractCancelled(contractData, userData) {
  const contract = contractData && typeof contractData === 'object' ? contractData : {};
  const user = userData && typeof userData === 'object' ? userData : {};

  if (user.contractCancelledAt != null) {
    return true;
  }
  if (String(user.contractStatus || '').trim().toLowerCase() === 'cancelled') {
    return true;
  }

  const contractStatus = String(contract.status || '').trim().toLowerCase();
  if (contractStatus === 'cancelled' || contractStatus === 'terminated') {
    return true;
  }
  if (contract.cancelledAt != null || contract.contractCancelledAt != null) {
    return true;
  }
  return false;
}

function buildMerchantWithdrawable(totalCredit, contractData, userData, walletData = {}) {
  const isCancelled = isContractCancelled(contractData, userData);
  const omiseWithdrawable = readMoney(walletData.omiseWithdrawableCredit);

  if (isCancelled) {
    return roundMoney(totalCredit + omiseWithdrawable);
  }
  return roundMoney(omiseWithdrawable);
}

function toHttpsErrorFromOmise(error, fallbackMessage, HttpsError) {
  if (error instanceof HttpsError) {
    return error;
  }
  const message = String(error?.message || error || fallbackMessage).trim();
  return new HttpsError('failed-precondition', message || fallbackMessage);
}

function createOmisePayoutHandlers(deps) {
  const {
    db,
    FieldValue,
    HttpsError,
    onCall,
    defineSecret,
    logger,
    DEFAULT_REGION,
  } = deps;

  const OMISE_SECRET_KEY = defineSecret('OMISE_SECRET_KEY');

  async function sumCreditBalance(tx, uid) {
    const creditsQuery = db.collection('credits').where('uid', '==', uid);
    const snapshot = await tx.get(creditsQuery);
    let total = 0;
    for (const doc of snapshot.docs) {
      total += readMoney(doc.data()?.amount);
    }
    return roundMoney(total);
  }

  async function sumPendingWithdrawAmount(tx, uid) {
    const pendingQuery = db
      .collection('withdraw_requests')
      .where('uid', '==', uid)
      .where('status', 'in', ACTIVE_WITHDRAW_STATUSES);
    const snapshot = await tx.get(pendingQuery);
    let total = 0;
    for (const doc of snapshot.docs) {
      total += readMoney(doc.data()?.amount);
    }
    return roundMoney(total);
  }

  async function loadPayoutProfile(uid, actorType) {
    const trimmedUid = String(uid || '').trim();
    if (actorType === 'rider') {
      const doc = await db.collection('riders').doc(trimmedUid).get();
      if (!doc.exists) {
        throw new HttpsError('failed-precondition', 'ไม่พบข้อมูลไรเดอร์');
      }
      const data = doc.data() || {};
      return {
        collection: 'riders',
        docRef: doc.ref,
        data,
        bankName: String(data.bankName || '').trim(),
        accountNumber: String(data.accountNumber || '').replace(/\D/g, ''),
        accountName: String(data.accountName || data.accountOwner || data.name || '').trim(),
        email: String(data.email || '').trim(),
        omiseRecipientId: String(data.omiseRecipientId || '').trim() || null,
      };
    }

    if (actorType === 'merchant') {
      const doc = await db.collection('users').doc(trimmedUid).get();
      if (!doc.exists) {
        throw new HttpsError('failed-precondition', 'ไม่พบข้อมูลร้านค้า');
      }
      const data = doc.data() || {};
      return {
        collection: 'users',
        docRef: doc.ref,
        data,
        bankName: String(data.bankName || '').trim(),
        accountNumber: String(
          data.accountNumber || data.bankAccountNumber || '',
        ).replace(/\D/g, ''),
        accountName: String(
          data.accountName || data.shopName || data.displayName || data.name || '',
        ).trim(),
        email: String(data.email || '').trim(),
        omiseRecipientId: String(data.omiseRecipientId || '').trim() || null,
      };
    }

    throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
  }

  function validateBankProfile(profile) {
    const brand = mapThaiBankToOmiseBrand(profile.bankName);
    if (!brand) {
      throw new HttpsError(
        'failed-precondition',
        'กรุณาระบุธนาคารที่รองรับในโปรไฟล์ (BBL, KBank, SCB, KTB, BAY, TTB)',
      );
    }
    if (!profile.accountNumber || profile.accountNumber.length < 10) {
      throw new HttpsError('failed-precondition', 'กรุณาระบุเลขบัญชีธนาคารให้ครบถ้วน');
    }
    if (!profile.accountName) {
      throw new HttpsError('failed-precondition', 'กรุณาระบุชื่อบัญชีให้ตรงธนาคาร');
    }
    return brand;
  }

  async function getOrCreateOmiseRecipient(secretKey, profile, brand, emailFallback) {
    if (profile.omiseRecipientId) {
      try {
        await omiseRequest(secretKey, 'GET', `/recipients/${profile.omiseRecipientId}`);
        return profile.omiseRecipientId;
      } catch (error) {
        logger.warn('omise recipient stale, recreating', {
          uid: profile.docRef.id,
          omiseRecipientId: profile.omiseRecipientId,
          error: String(error?.message || error),
        });
      }
    }

    const recipient = await omiseRequest(secretKey, 'POST', '/recipients', {
      name: profile.accountName,
      email: profile.email || emailFallback || undefined,
      type: 'individual',
      bank_account: {
        brand,
        number: profile.accountNumber,
        name: profile.accountName,
      },
    });

    const recipientId = String(recipient?.id || '').trim();
    if (!recipientId) {
      throw new Error('Omise ไม่คืน recipient id');
    }

    await profile.docRef.set(
      {
        omiseRecipientId: recipientId,
        omiseRecipientUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return recipientId;
  }

  async function computeWithdrawableBalance(uid, actorType, tx = null) {
    const read = tx
      ? (ref) => tx.get(ref)
      : (ref) => ref.get();

    if (actorType === 'rider') {
      const creditSnap = await read(db.collection('credits').where('uid', '==', uid));

      let creditTotal = 0;
      for (const doc of creditSnap.docs) {
        creditTotal += readMoney(doc.data()?.amount);
      }

      return {
        availableBalance: roundMoney(Math.max(0, creditTotal)),
        creditTotal: roundMoney(creditTotal),
        pendingWithdrawTotal: 0,
      };
    }

    const [creditSnap, walletDoc, userDoc, contractDoc] = await Promise.all([
      read(db.collection('credits').where('uid', '==', uid)),
      read(db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid)),
      read(db.collection('users').doc(uid)),
      read(db.collection('contracts').doc(uid)),
    ]);

    let totalCredit = 0;
    for (const doc of creditSnap.docs) {
      totalCredit += readMoney(doc.data()?.amount);
    }

    const withdrawable = buildMerchantWithdrawable(
      roundMoney(totalCredit),
      contractDoc.exists ? contractDoc.data() || {} : {},
      userDoc.exists ? userDoc.data() || {} : {},
      walletDoc.exists ? walletDoc.data() || {} : {},
    );

    return {
      availableBalance: roundMoney(Math.max(0, withdrawable)),
      creditTotal: roundMoney(totalCredit),
      pendingWithdrawTotal: 0,
      withdrawableBeforePending: withdrawable,
      isContractCancelled: isContractCancelled(
        contractDoc.exists ? contractDoc.data() || {} : {},
        userDoc.exists ? userDoc.data() || {} : {},
      ),
    };
  }

  async function reserveWithdrawLedger(tx, {
    uid,
    actorType,
    amount,
    withdrawRef,
    withdrawRequestId,
  }) {
    const reservedCreditIds = [];

    if (actorType === 'rider') {
      const creditDocId = `withdraw_hold_${withdrawRequestId}`;
      const creditRef = db.collection('credits').doc(creditDocId);
      tx.set(creditRef, {
        uid,
        amount: -amount,
        timestamp: FieldValue.serverTimestamp(),
        type: 'withdraw_hold',
        withdrawRequestId,
        creditedByCloudFunction: true,
      });
      reservedCreditIds.push(creditDocId);
      return { reservedCreditIds, omiseDebit: amount, creditDebit: 0 };
    }

    const [walletDoc, userDoc, contractDoc, creditSnap] = await Promise.all([
      tx.get(db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid)),
      tx.get(db.collection('users').doc(uid)),
      tx.get(db.collection('contracts').doc(uid)),
      tx.get(db.collection('credits').where('uid', '==', uid)),
    ]);

    let totalCredit = 0;
    for (const doc of creditSnap.docs) {
      totalCredit += readMoney(doc.data()?.amount);
    }

    const walletData = walletDoc.exists ? walletDoc.data() || {} : {};
    const omiseWithdrawable = readMoney(walletData.omiseWithdrawableCredit);
    const isCancelled = isContractCancelled(
      contractDoc.exists ? contractDoc.data() || {} : {},
      userDoc.exists ? userDoc.data() || {} : {},
    );

    const withdrawable = buildMerchantWithdrawable(
      roundMoney(totalCredit),
      contractDoc.exists ? contractDoc.data() || {} : {},
      userDoc.exists ? userDoc.data() || {} : {},
      walletData,
    );

    if (amount > withdrawable + 0.001) {
      throw new HttpsError(
        'failed-precondition',
        `ยอดถอนเกินที่ถอนได้ (ถอนได้ ${withdrawable.toFixed(2)} บาท)`,
      );
    }

    const omiseDebit = roundMoney(Math.min(amount, omiseWithdrawable));
    const creditDebit = roundMoney(amount - omiseDebit);

    if (omiseDebit > 0) {
      tx.set(
        db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid),
        {
          omiseWithdrawableCredit: FieldValue.increment(-omiseDebit),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    if (creditDebit > 0) {
      if (!isCancelled) {
        throw new HttpsError(
          'failed-precondition',
          'ไม่สามารถถอนเครดิตที่ล็อกไว้ได้จนกว่าจะยกเลิกสัญญาร้าน',
        );
      }
      const creditDocId = `withdraw_hold_${withdrawRequestId}`;
      const creditRef = db.collection('credits').doc(creditDocId);
      tx.set(creditRef, {
        uid,
        amount: -creditDebit,
        timestamp: FieldValue.serverTimestamp(),
        type: 'withdraw_hold',
        withdrawRequestId,
        creditedByCloudFunction: true,
      });
      reservedCreditIds.push(creditDocId);
    }

    return { reservedCreditIds, omiseDebit, creditDebit };
  }

  async function rollbackWithdrawReservation(withdrawDoc) {
    const data = withdrawDoc.data() || {};
    const uid = String(data.uid || '').trim();
    const actorType = String(data.actorType || 'rider').trim();
    const amount = readMoney(data.amount);
    const reservedCreditIds = Array.isArray(data.reservedCreditIds)
      ? data.reservedCreditIds.map((value) => String(value || '').trim()).filter(Boolean)
      : [];
    const omiseDebit = readMoney(data.omiseDebit);
    const creditDebit = readMoney(data.creditDebit);

    const batch = db.batch();

    for (const creditId of reservedCreditIds) {
      batch.delete(db.collection('credits').doc(creditId));
    }

    if (actorType === 'merchant' && omiseDebit > 0) {
      batch.set(
        db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid),
        {
          omiseWithdrawableCredit: FieldValue.increment(omiseDebit),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    batch.set(
      withdrawDoc.ref,
      {
        status: 'failed',
        failureMessage: data.failureMessage || 'transfer failed',
        rolledBackAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await batch.commit();

    logger.info('withdraw reservation rolled back', {
      withdrawRequestId: withdrawDoc.id,
      uid,
      actorType,
      amount,
      omiseDebit,
      creditDebit,
    });
  }

  async function finalizeWithdrawPaid(withdrawDoc, transferData = {}) {
    const data = withdrawDoc.data() || {};
    const uid = String(data.uid || '').trim();
    const actorType = String(data.actorType || 'rider').trim();
    const amount = readMoney(data.amount);
    const reservedCreditIds = Array.isArray(data.reservedCreditIds)
      ? data.reservedCreditIds
      : [];

    const batch = db.batch();

    for (const creditId of reservedCreditIds) {
      batch.set(
        db.collection('credits').doc(String(creditId)),
        {
          type: 'withdraw_paid',
          paidAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    batch.set(
      withdrawDoc.ref,
      {
        status: 'paid',
        paidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        omiseTransferStatus: transferData?.paid === true ? 'paid' : transferData?.status || 'paid',
      },
      { merge: true },
    );

    const targetApp = actorType === 'merchant' ? 'van1' : 'van3';
    const notifRef = db.collection('app_notifications').doc();
    batch.set(notifRef, {
      targetApp,
      recipientUid: uid,
      title: 'ถอนเงินสำเร็จ',
      body: `โอน ${amount.toFixed(2)} บาทเข้าบัญชีของคุณแล้ว`,
      action: 'payout_paid',
      sourceApp: 'cloud_function',
      read: false,
      isRead: false,
      withdrawRequestId: withdrawDoc.id,
      createdAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  function isOmiseTransferPaid(transfer) {
    return transfer?.paid === true || String(transfer?.state || '').trim() === 'paid';
  }

  function isOmiseTransferFailed(transfer) {
    const state = String(transfer?.state || '').trim();
    return state === 'failed' || Boolean(transfer?.failure_code);
  }

  function readTimestampMillis(value) {
    if (value && typeof value.toDate === 'function') {
      return value.toDate().getTime();
    }
    if (value instanceof Date) {
      return value.getTime();
    }
    return null;
  }

  async function applyTransferOutcome(withdrawRef, transfer) {
    const withdrawDoc = await withdrawRef.get();
    if (!withdrawDoc.exists) {
      return 'missing';
    }

    const status = String(withdrawDoc.data()?.status || '').trim();
    if (status === 'paid' || status === 'failed' || status === 'cancelled') {
      return status;
    }

    if (isOmiseTransferPaid(transfer)) {
      await finalizeWithdrawPaid(withdrawDoc, transfer);
      return 'paid';
    }

    if (isOmiseTransferFailed(transfer)) {
      await withdrawDoc.ref.set(
        {
          failureMessage:
            transfer?.failure_message ||
            transfer?.failure_code ||
            'transfer failed',
        },
        { merge: true },
      );
      await rollbackWithdrawReservation(withdrawDoc);
      return 'failed';
    }

    await withdrawDoc.ref.set(
      {
        omiseTransferStatus: transfer?.state || withdrawDoc.data()?.omiseTransferStatus || 'pending',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return String(withdrawDoc.data()?.status || 'submitted');
  }

  async function syncWithdrawRequestWithOmise(withdrawDoc, secretKey) {
    const data = withdrawDoc.data() || {};
    const status = String(data.status || '').trim();
    if (!ACTIVE_WITHDRAW_STATUSES.includes(status)) {
      return status;
    }

    const transferId = String(data.omiseTransferId || '').trim();
    if (!transferId) {
      return status;
    }

    try {
      const transfer = await omiseRequest(secretKey, 'GET', `/transfers/${transferId}`);
      const outcome = await applyTransferOutcome(withdrawDoc.ref, transfer);
      if (outcome === 'paid' || outcome === 'failed') {
        return outcome;
      }

      const submittedAt =
        readTimestampMillis(data.submittedAt) || readTimestampMillis(data.timestamp);
      const ageMs = submittedAt ? Date.now() - submittedAt : 0;
      if (ageMs > STALE_WITHDRAW_MS) {
        logger.warn('stale withdraw transfer still pending; rolling back reservation', {
          withdrawRequestId: withdrawDoc.id,
          transferId,
          omiseState: transfer?.state,
          ageMs,
        });
        const freshDoc = await withdrawDoc.ref.get();
        await freshDoc.ref.set(
          {
            failureMessage:
              'Omise transfer did not complete in time; reservation released for retry',
          },
          { merge: true },
        );
        await rollbackWithdrawReservation(freshDoc);
        return 'failed';
      }

      return outcome;
    } catch (error) {
      logger.warn('syncWithdrawRequestWithOmise failed', {
        withdrawRequestId: withdrawDoc.id,
        transferId,
        error: String(error?.message || error),
      });
      return status;
    }
  }

  async function reconcileActiveWithdrawRequests(uid, secretKey) {
    const snapshot = await db
      .collection('withdraw_requests')
      .where('uid', '==', uid)
      .where('status', 'in', ACTIVE_WITHDRAW_STATUSES)
      .get();

    for (const doc of snapshot.docs) {
      await syncWithdrawRequestWithOmise(doc, secretKey);
    }
  }

  async function handleTransferWebhook(event) {
    const eventType = String(event?.key || event?.type || '').trim();
    if (!eventType.startsWith('transfer.')) {
      return false;
    }

    const transferData =
      event?.data && typeof event.data === 'object' ? event.data : event;
    const transferId = String(transferData?.id || '').trim();
    const metadata = transferData?.metadata && typeof transferData.metadata === 'object'
      ? transferData.metadata
      : {};
    const withdrawRequestId = String(metadata.withdrawRequestId || '').trim();

    let withdrawDoc = null;
    if (withdrawRequestId) {
      const doc = await db.collection('withdraw_requests').doc(withdrawRequestId).get();
      if (doc.exists) {
        withdrawDoc = doc;
      }
    }

    if (!withdrawDoc && transferId) {
      const snapshot = await db
        .collection('withdraw_requests')
        .where('omiseTransferId', '==', transferId)
        .limit(1)
        .get();
      if (!snapshot.empty) {
        withdrawDoc = snapshot.docs[0];
      }
    }

    if (!withdrawDoc) {
      logger.warn('transfer webhook without matching withdraw request', {
        eventType,
        transferId,
        withdrawRequestId,
      });
      return true;
    }

    const currentStatus = String(withdrawDoc.data()?.status || '').trim();
    if (currentStatus === 'paid' || currentStatus === 'failed') {
      return true;
    }

    const isPaid =
      eventType === 'transfer.paid' ||
      transferData?.paid === true ||
      transferData?.state === 'paid';
    const isFailed =
      eventType === 'transfer.failed' ||
      transferData?.state === 'failed' ||
      Boolean(transferData?.failure_code);

    if (isPaid) {
      await finalizeWithdrawPaid(withdrawDoc, transferData);
      return true;
    }

    if (isFailed) {
      await withdrawDoc.ref.set(
        {
          failureMessage:
            transferData?.failure_message ||
            transferData?.failure_code ||
            'transfer failed',
        },
        { merge: true },
      );
      await rollbackWithdrawReservation(withdrawDoc);
      return true;
    }

    if (eventType === 'transfer.send' || eventType === 'transfer.create') {
      await withdrawDoc.ref.set(
        {
          status: 'submitted',
          omiseTransferStatus: transferData?.state || eventType,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return true;
  }

  const getWithdrawableBalance = onCall(
    { region: DEFAULT_REGION },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const uid = String(request.auth.uid).trim();
      const actorType = String(request.data?.actorType || 'rider').trim();
      if (actorType !== 'rider' && actorType !== 'merchant') {
        throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
      }

      const balance = await computeWithdrawableBalance(uid, actorType);
      let bankLabel = null;
      let accountName = null;

      try {
        const profile = await loadPayoutProfile(uid, actorType);
        const brand = mapThaiBankToOmiseBrand(profile.bankName);
        bankLabel = brand
          ? `${profile.bankName} ${maskAccountNumber(profile.accountNumber)}`
          : null;
        accountName = profile.accountName || null;
      } catch (_) {
        // Profile may be incomplete; UI can still show balance.
      }

      return {
        uid,
        actorType,
        ...balance,
        minWithdrawAmount: MIN_WITHDRAW_BAHT,
        bankLabel,
        accountName,
        hasBankProfile: Boolean(bankLabel && accountName),
      };
    },
  );

  const requestOmiseWithdraw = onCall(
    {
      region: DEFAULT_REGION,
      secrets: [OMISE_SECRET_KEY],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const uid = String(request.auth.uid).trim();
      const actorType = String(request.data?.actorType || 'rider').trim();
      const amount = roundMoney(request.data?.amount);

      if (actorType !== 'rider' && actorType !== 'merchant') {
        throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
      }
      if (!Number.isFinite(amount) || amount < MIN_WITHDRAW_BAHT) {
        throw new HttpsError(
          'invalid-argument',
          `ยอดถอนขั้นต่ำ ${MIN_WITHDRAW_BAHT} บาท`,
        );
      }

      const profile = await loadPayoutProfile(uid, actorType);
      const brand = validateBankProfile(profile);
      const secretKey = OMISE_SECRET_KEY.value();

      await reconcileActiveWithdrawRequests(uid, secretKey);

      const reservation = await db.runTransaction(async (tx) => {
        const balanceInfo = await computeWithdrawableBalance(uid, actorType, tx);
        if (amount > balanceInfo.availableBalance + 0.001) {
          throw new HttpsError(
            'failed-precondition',
            `ยอดถอนเกินที่ถอนได้ (ถอนได้ ${balanceInfo.availableBalance.toFixed(2)} บาท)`,
          );
        }

        const pendingQuery = db
          .collection('withdraw_requests')
          .where('uid', '==', uid)
          .where('status', 'in', ACTIVE_WITHDRAW_STATUSES);
        const pendingSnap = await tx.get(pendingQuery);
        if (!pendingSnap.empty) {
          throw new HttpsError(
            'already-exists',
            'มีคำขอถอนเงินที่กำลังดำเนินการอยู่แล้ว',
          );
        }

        const withdrawRef = db.collection('withdraw_requests').doc();
        const ledger = await reserveWithdrawLedger(tx, {
          uid,
          actorType,
          amount,
          withdrawRef,
          withdrawRequestId: withdrawRef.id,
        });

        tx.set(withdrawRef, {
          uid,
          actorType,
          amount,
          status: 'processing',
          timestamp: FieldValue.serverTimestamp(),
          requestedByCloudFunction: true,
          bankSnapshot: {
            brand,
            bankName: profile.bankName,
            last4: profile.accountNumber.slice(-4),
            accountName: profile.accountName,
          },
          reservedCreditIds: ledger.reservedCreditIds,
          omiseDebit: ledger.omiseDebit,
          creditDebit: ledger.creditDebit,
        });

        return {
          withdrawRequestId: withdrawRef.id,
          withdrawRef,
        };
      });

      const emailFallback = String(request.auth.token?.email || '').trim();

      try {
        const recipientId = await getOrCreateOmiseRecipient(
          secretKey,
          profile,
          brand,
          emailFallback,
        );

        const amountSatang = Math.round(amount * 100);
        const transfer = await omiseRequest(secretKey, 'POST', '/transfers', {
          amount: amountSatang,
          recipient: recipientId,
          metadata: {
            withdrawRequestId: reservation.withdrawRequestId,
            uid,
            actorType,
          },
        });

        const transferId = String(transfer?.id || '').trim();
        await reservation.withdrawRef.set(
          {
            status: 'submitted',
            omiseTransferId: transferId || null,
            omiseRecipientId: recipientId,
            omiseTransferStatus: transfer?.state || 'pending',
            submittedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        let finalStatus = 'submitted';
        if (transferId) {
          const latestTransfer = await omiseRequest(
            secretKey,
            'GET',
            `/transfers/${transferId}`,
          );
          finalStatus = await applyTransferOutcome(
            reservation.withdrawRef,
            latestTransfer,
          );
        } else if (isOmiseTransferPaid(transfer)) {
          const paidDoc = await reservation.withdrawRef.get();
          await finalizeWithdrawPaid(paidDoc, transfer);
          finalStatus = 'paid';
        }

        return {
          success: true,
          withdrawRequestId: reservation.withdrawRequestId,
          amount,
          omiseTransferId: transferId || null,
          status: finalStatus === 'paid' ? 'paid' : 'submitted',
        };
      } catch (error) {
        logger.error('requestOmiseWithdraw omise failed', {
          uid,
          actorType,
          amount,
          withdrawRequestId: reservation.withdrawRequestId,
          error: String(error?.message || error),
        });

        const failedDoc = await reservation.withdrawRef.get();
        await reservation.withdrawRef.set(
          {
            failureMessage: String(error?.message || error),
          },
          { merge: true },
        );
        await rollbackWithdrawReservation(failedDoc);

        throw toHttpsErrorFromOmise(error, 'ไม่สามารถถอนเงินผ่าน Omise ได้', HttpsError);
      }
    },
  );

  return {
    getWithdrawableBalance,
    requestOmiseWithdraw,
    handleTransferWebhook,
    rollbackWithdrawReservation,
    finalizeWithdrawPaid,
  };
}

module.exports = {
  createOmisePayoutHandlers,
  mapThaiBankToOmiseBrand,
  MIN_WITHDRAW_BAHT,
};
