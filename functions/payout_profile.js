const MIN_WITHDRAW_BAHT = 30;
const ACTIVE_WITHDRAW_STATUSES = ['pending', 'processing', 'submitted'];
const MANUAL_ACTIVE_WITHDRAW_STATUSES = ['pending_admin', ...ACTIVE_WITHDRAW_STATUSES];
const MERCHANT_WALLETS_COLLECTION = 'merchant_wallets';
const MERCHANT_SHOP_REGISTRATION_COLLECTIONS = [
  'shop_registrations',
  'market_registrations',
  'restaurant_registrations',
  'pharmacy_registrations',
  'other_registrations',
];

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

function maskPromptPayId(promptPayId) {
  const digits = String(promptPayId || '').replace(/\D/g, '');
  if (digits.length <= 4) {
    return digits;
  }
  return `••••${digits.slice(-4)}`;
}

function readBankFieldsFromData(data) {
  const source = data && typeof data === 'object' ? data : {};
  return {
    bankName: String(source.bankName || source.bank || '').trim(),
    accountNumber: String(
      source.accountNumber || source.bankAccountNumber || source.accountNo || '',
    ).replace(/\D/g, ''),
    accountName: String(
      source.accountName ||
        source.accountOwner ||
        source.ownerName ||
        source.accountHolder ||
        source.accountHolderName ||
        source.shopName ||
        source.displayName ||
        source.name ||
        '',
    ).trim(),
    email: String(source.email || source.contactEmail || '').trim(),
    omiseRecipientId: String(source.omiseRecipientId || '').trim() || null,
  };
}

function readPromptPayFieldsFromData(data) {
  const source = data && typeof data === 'object' ? data : {};
  return {
    promptPayPhoneNumber: String(source.promptPayPhoneNumber || '').replace(/\D/g, ''),
    promptPayNationalId: String(
      source.promptPayNationalId ||
        source.promptPayNationalIdOrTaxId ||
        source.promptPayId ||
        '',
    ).replace(/\D/g, ''),
  };
}

function resolvePromptPayId(profile) {
  const nationalId = String(profile.promptPayNationalId || '').replace(/\D/g, '');
  if (nationalId.length === 13) {
    return nationalId;
  }
  const phone = String(profile.promptPayPhoneNumber || '').replace(/\D/g, '');
  if (phone.length >= 9 && phone.length <= 10) {
    return phone;
  }
  return null;
}

function hasValidPromptPayProfile(profile) {
  return Boolean(resolvePromptPayId(profile));
}

function hasValidBankProfile(profile) {
  const brand = mapThaiBankToOmiseBrand(profile.bankName);
  return Boolean(
    brand &&
      profile.accountNumber &&
      profile.accountNumber.length >= 10 &&
      profile.accountName,
  );
}

function mapServiceTypeToRegistrationCollection(serviceType) {
  const normalized = String(serviceType || '').trim().toLowerCase();
  if (normalized === 'ตลาด' || normalized === 'market') {
    return 'market_registrations';
  }
  if (
    normalized === 'ร้านค้า' ||
    normalized === 'shop' ||
    normalized === 'store'
  ) {
    return 'shop_registrations';
  }
  if (
    normalized === 'ร้านอาหาร' ||
    normalized === 'restaurant' ||
    normalized === 'food'
  ) {
    return 'restaurant_registrations';
  }
  if (normalized === 'ร้านขายยา' || normalized === 'pharmacy') {
    return 'pharmacy_registrations';
  }
  if (
    normalized === 'อื่นๆ' ||
    normalized === 'อื่น' ||
    normalized === 'other' ||
    normalized === 'others'
  ) {
    return 'other_registrations';
  }
  return null;
}

async function findMerchantShopRegistrationDoc(db, collection, uid) {
  const ref = db.collection(collection);
  const directDoc = await ref.doc(uid).get();
  if (directDoc.exists) {
    return directDoc.data() || {};
  }

  const ownerQuery = await ref.where('ownerId', '==', uid).limit(1).get();
  if (!ownerQuery.empty) {
    return ownerQuery.docs[0].data() || {};
  }

  return null;
}

async function loadMerchantShopRegistration(db, uid) {
  const trimmedUid = String(uid || '').trim();
  let preferredCollection = null;

  try {
    const contractDoc = await db.collection('contracts').doc(trimmedUid).get();
    if (contractDoc.exists) {
      preferredCollection = mapServiceTypeToRegistrationCollection(
        contractDoc.data()?.serviceType,
      );
      if (preferredCollection) {
        const preferredData = await findMerchantShopRegistrationDoc(
          db,
          preferredCollection,
          trimmedUid,
        );
        if (preferredData) {
          return { collection: preferredCollection, data: preferredData };
        }
      }
    }
  } catch (_) {
    // Contract lookup is best-effort.
  }

  for (const collection of MERCHANT_SHOP_REGISTRATION_COLLECTIONS) {
    if (collection === preferredCollection) {
      continue;
    }
    const data = await findMerchantShopRegistrationDoc(db, collection, trimmedUid);
    if (data) {
      return { collection, data };
    }
  }

  return null;
}

function createPayoutProfileLoader(db, HttpsError) {
  async function loadPayoutProfile(uid, actorType) {
    const trimmedUid = String(uid || '').trim();
    if (actorType === 'rider') {
      const doc = await db.collection('riders').doc(trimmedUid).get();
      if (!doc.exists) {
        throw new HttpsError('failed-precondition', 'ไม่พบข้อมูลไรเดอร์');
      }
      const data = doc.data() || {};
      const bank = readBankFieldsFromData(data);
      const promptPay = readPromptPayFieldsFromData(data);
      return {
        collection: 'riders',
        docRef: doc.ref,
        data,
        ...bank,
        ...promptPay,
      };
    }

    if (actorType === 'merchant') {
      const userDoc = await db.collection('users').doc(trimmedUid).get();
      const userData = userDoc.exists ? userDoc.data() || {} : {};
      const userBank = readBankFieldsFromData(userData);
      const userPromptPay = readPromptPayFieldsFromData(userData);

      let shopReg = null;
      let shopBank = readBankFieldsFromData({});
      let shopPromptPay = readPromptPayFieldsFromData({});
      const needsShopLookup =
        !userBank.bankName ||
        !userBank.accountNumber ||
        !userBank.accountName ||
        !resolvePromptPayId(userPromptPay);
      if (needsShopLookup) {
        shopReg = await loadMerchantShopRegistration(db, trimmedUid);
        if (shopReg) {
          shopBank = readBankFieldsFromData(shopReg.data);
          shopPromptPay = readPromptPayFieldsFromData(shopReg.data);
        }
      }

      if (!userDoc.exists && !shopReg) {
        throw new HttpsError('failed-precondition', 'ไม่พบข้อมูลร้านค้า');
      }

      return {
        collection: 'users',
        docRef: db.collection('users').doc(trimmedUid),
        data: { ...(shopReg?.data || {}), ...userData },
        bankName: userBank.bankName || shopBank.bankName,
        accountNumber: userBank.accountNumber || shopBank.accountNumber,
        accountName: userBank.accountName || shopBank.accountName,
        email: userBank.email || shopBank.email,
        omiseRecipientId: userBank.omiseRecipientId || shopBank.omiseRecipientId,
        promptPayPhoneNumber:
          userPromptPay.promptPayPhoneNumber || shopPromptPay.promptPayPhoneNumber,
        promptPayNationalId:
          userPromptPay.promptPayNationalId || shopPromptPay.promptPayNationalId,
      };
    }

    throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
  }

  return { loadPayoutProfile };
}

function isContractCancelled(contractData) {
  const contract = contractData && typeof contractData === 'object' ? contractData : {};
  const contractStatus = String(contract.status || '').trim().toLowerCase();
  if (contractStatus === 'cancelled' || contractStatus === 'terminated') {
    return true;
  }
  if (contract.cancelledAt != null || contract.contractCancelledAt != null) {
    return true;
  }
  return false;
}

function buildMerchantWithdrawable(totalCredit, contractData, walletData = {}) {
  const isCancelled = isContractCancelled(contractData);
  const omiseWithdrawable = readMoney(walletData.omiseWithdrawableCredit);

  if (isCancelled) {
    return roundMoney(totalCredit + omiseWithdrawable);
  }
  return roundMoney(omiseWithdrawable);
}

function createPayoutLedger(deps) {
  const { db, FieldValue, HttpsError } = deps;

  async function computeWithdrawableBalance(uid, actorType, tx = null) {
    const read = tx ? (ref) => tx.get(ref) : (ref) => ref.get();

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

    const [creditSnap, walletDoc, contractDoc] = await Promise.all([
      read(db.collection('credits').where('uid', '==', uid)),
      read(db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid)),
      read(db.collection('contracts').doc(uid)),
    ]);

    let totalCredit = 0;
    for (const doc of creditSnap.docs) {
      totalCredit += readMoney(doc.data()?.amount);
    }

    const withdrawable = buildMerchantWithdrawable(
      roundMoney(totalCredit),
      contractDoc.exists ? contractDoc.data() || {} : {},
      walletDoc.exists ? walletDoc.data() || {} : {},
    );

    return {
      availableBalance: roundMoney(Math.max(0, withdrawable)),
      creditTotal: roundMoney(totalCredit),
      pendingWithdrawTotal: 0,
      withdrawableBeforePending: withdrawable,
      isContractCancelled: isContractCancelled(
        contractDoc.exists ? contractDoc.data() || {} : {},
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

    const [walletDoc, contractDoc, creditSnap] = await Promise.all([
      tx.get(db.collection(MERCHANT_WALLETS_COLLECTION).doc(uid)),
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
    );

    const withdrawable = buildMerchantWithdrawable(
      roundMoney(totalCredit),
      contractDoc.exists ? contractDoc.data() || {} : {},
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
    const reservedCreditIds = Array.isArray(data.reservedCreditIds)
      ? data.reservedCreditIds.map((value) => String(value || '').trim()).filter(Boolean)
      : [];
    const omiseDebit = readMoney(data.omiseDebit);

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
        payoutChannel: data.payoutChannel || 'manual',
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

  return {
    computeWithdrawableBalance,
    reserveWithdrawLedger,
    rollbackWithdrawReservation,
    finalizeWithdrawPaid,
  };
}

module.exports = {
  MIN_WITHDRAW_BAHT,
  ACTIVE_WITHDRAW_STATUSES,
  MANUAL_ACTIVE_WITHDRAW_STATUSES,
  MERCHANT_WALLETS_COLLECTION,
  readMoney,
  roundMoney,
  mapThaiBankToOmiseBrand,
  maskAccountNumber,
  maskPromptPayId,
  readBankFieldsFromData,
  readPromptPayFieldsFromData,
  resolvePromptPayId,
  hasValidPromptPayProfile,
  hasValidBankProfile,
  createPayoutProfileLoader,
  createPayoutLedger,
  isContractCancelled,
  buildMerchantWithdrawable,
};
