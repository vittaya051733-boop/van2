const { assertVan4Admin, assertAdminBranchAccess, resolveMerchantBranchId } = require('./social/admin_guard');
const { DEFAULT_WITHDRAW_FEE_BAHT } = require('./settlement_config');
const {
  MIN_WITHDRAW_BAHT,
  mapThaiBankToOmiseBrand,
  readMoney,
  roundMoney,
  resolvePromptPayId,
  maskPromptPayId,
  maskAccountNumber,
  hasValidBankProfile,
  hasValidPromptPayProfile,
  MANUAL_ACTIVE_WITHDRAW_STATUSES,
} = require('./payout_profile');

function normalizeDigits(value) {
  return String(value || '').replace(/\D/g, '');
}

function exactDigitsMatch(actual, expected) {
  const a = normalizeDigits(actual);
  const e = normalizeDigits(expected);
  return Boolean(a && e && a === e);
}

function promptPayTargets(id) {
  const digits = normalizeDigits(id);
  if (!digits) {
    return [];
  }
  const targets = new Set([digits]);
  if (digits.length >= 9 && digits.length <= 10) {
    const local = digits.startsWith('0') ? digits.slice(1) : digits;
    targets.add(`66${local}`);
    targets.add(`0${local}`);
  }
  return [...targets];
}

function validateWithdrawSlipReceiver(providerPayload, payoutDestination, payoutMethod) {
  const receiver = providerPayload?.data?.receiver || {};
  const accountValue = String(receiver?.account?.value || '').trim();
  const proxyValue = String(receiver?.proxy?.value || '').trim();
  const actualTargets = [accountValue, proxyValue].filter(Boolean);

  if (payoutMethod === 'promptpay') {
    const expectedTargets = promptPayTargets(payoutDestination?.promptPayId);
    const matched =
      actualTargets.length > 0 &&
      expectedTargets.some((expected) =>
        actualTargets.some((actual) => exactDigitsMatch(actual, expected)),
      );
    return { matched, expectedTargets, actualTargets };
  }

  const expectedAccount = normalizeDigits(payoutDestination?.accountNumber);
  const matched =
    expectedAccount.length > 0 &&
    actualTargets.some((actual) => exactDigitsMatch(actual, expectedAccount));
  return { matched, expectedAccount, actualTargets };
}

function buildFullPayoutDestinationSnapshot(profile) {
  const hasPP = hasValidPromptPayProfile(profile);
  const hasBank = hasValidBankProfile(profile);
  const promptPayId = hasPP ? resolvePromptPayId(profile) : null;

  return {
    type: 'both',
    hasPromptPay: hasPP,
    hasBank,
    promptPayId,
    promptPayMasked: hasPP ? maskPromptPayId(promptPayId) : null,
    bankName: hasBank ? profile.bankName : null,
    accountNumber: hasBank ? profile.accountNumber : null,
    accountName: hasBank
      ? profile.accountName
      : profile.accountName || profile.data?.name || null,
    last4: hasBank ? profile.accountNumber.slice(-4) : null,
    brand: hasBank ? mapThaiBankToOmiseBrand(profile.bankName) : null,
  };
}

function buildPayoutDestinationSnapshot(profile, payoutMethod) {
  if (payoutMethod === 'promptpay') {
    const promptPayId = resolvePromptPayId(profile);
    return {
      type: 'promptpay',
      promptPayId,
      promptPayMasked: maskPromptPayId(promptPayId),
      accountName: profile.accountName || profile.data?.name || null,
    };
  }

  return {
    type: 'bank',
    bankName: profile.bankName,
    accountNumber: profile.accountNumber,
    accountName: profile.accountName,
    last4: profile.accountNumber.slice(-4),
    brand: mapThaiBankToOmiseBrand(profile.bankName),
    promptPayId: resolvePromptPayId(profile),
    promptPayMasked: hasValidPromptPayProfile(profile)
      ? maskPromptPayId(resolvePromptPayId(profile))
      : null,
  };
}

function csvCell(value) {
  const text = String(value ?? '');
  if (text.includes(',') || text.includes('"') || text.includes('\n')) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function resolveWithdrawFeeBaht(config) {
  const fee = readMoney(config?.withdrawFeeBaht);
  if (!Number.isFinite(fee) || fee < 0) {
    return DEFAULT_WITHDRAW_FEE_BAHT;
  }
  return roundMoney(fee);
}

function resolveNetPayout(data) {
  const amount = readMoney(data?.amount);
  if (data?.netPayout != null) {
    return roundMoney(data.netPayout);
  }
  const fee =
    data?.withdrawFeeBaht != null
      ? readMoney(data.withdrawFeeBaht)
      : 0;
  return roundMoney(Math.max(0, amount - fee));
}

function formatCsvTimestamp(value) {
  if (!value) {
    return '';
  }
  if (typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return String(value);
}

function createManualPayoutHandlers(deps) {
  const {
    admin,
    db,
    FieldValue,
    HttpsError,
    onCall,
    defineSecret,
    logger,
    DEFAULT_REGION,
    payoutLedger,
    loadSettlementConfig,
    verifyStandaloneSlipCore,
    slipVerificationDeps,
  } = deps;

  const SLIPOK_API_KEY_SECRET = defineSecret('SLIPOK_API_KEY');

  const {
    loadPayoutProfile,
    computeWithdrawableBalance,
    reserveWithdrawLedger,
    rollbackWithdrawReservation,
    finalizeWithdrawPaid,
  } = payoutLedger;

  async function sumPendingWithdrawAmount(tx, uid) {
    const pendingQuery = db
      .collection('withdraw_requests')
      .where('uid', '==', uid)
      .where('status', 'in', MANUAL_ACTIVE_WITHDRAW_STATUSES);
    const snapshot = await tx.get(pendingQuery);
    let total = 0;
    for (const doc of snapshot.docs) {
      total += readMoney(doc.data()?.amount);
    }
    return roundMoney(total);
  }

  const requestManualWithdraw = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const uid = String(request.auth.uid).trim();
    const actorType = String(request.data?.actorType || 'rider').trim();
    const amount = roundMoney(request.data?.amount);

    const config = await loadSettlementConfig().catch(() => null);
    const withdrawFeeBaht = resolveWithdrawFeeBaht(config);
    const minGrossWithdrawAmount = roundMoney(MIN_WITHDRAW_BAHT + withdrawFeeBaht);
    const netPayout = roundMoney(amount - withdrawFeeBaht);

    if (actorType !== 'rider' && actorType !== 'merchant') {
      throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
    }
    if (!Number.isFinite(amount) || amount < minGrossWithdrawAmount) {
      throw new HttpsError(
        'invalid-argument',
        withdrawFeeBaht > 0
          ? `ยอดถอนขั้นต่ำ ${MIN_WITHDRAW_BAHT} บาท (หลังหักค่าบริการ ${withdrawFeeBaht.toFixed(2)} บาท) — ระบุจากกระเป๋าอย่างน้อย ${minGrossWithdrawAmount.toFixed(2)} บาท`
          : `ยอดถอนขั้นต่ำ ${MIN_WITHDRAW_BAHT} บาท`,
      );
    }
    if (netPayout + 0.001 < MIN_WITHDRAW_BAHT) {
      throw new HttpsError(
        'invalid-argument',
        `ยอดที่ได้รับหลังหักค่าบริการต้องไม่ต่ำกว่า ${MIN_WITHDRAW_BAHT} บาท`,
      );
    }

    const profile = await loadPayoutProfile(uid, actorType);
    const hasPP = hasValidPromptPayProfile(profile);
    const hasBank = hasValidBankProfile(profile);
    if (!hasPP && !hasBank) {
      throw new HttpsError(
        'failed-precondition',
        'กรุณาลงทะเบียน PromptPay หรือบัญชีธนาคารก่อนถอนเงิน',
      );
    }

    const payoutDestination = buildFullPayoutDestinationSnapshot(profile);
    const payoutMethod = 'admin_choice';

    const reservation = await db.runTransaction(async (tx) => {
      const balanceInfo = await computeWithdrawableBalance(uid, actorType, tx);
      if (amount > balanceInfo.availableBalance + 0.001) {
        throw new HttpsError(
          'failed-precondition',
          `ยอดถอนเกินที่ถอนได้ (ถอนได้ ${balanceInfo.availableBalance.toFixed(2)} บาท)`,
        );
      }

      const pendingTotal = await sumPendingWithdrawAmount(tx, uid);
      if (pendingTotal > 0) {
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
        withdrawFeeBaht,
        netPayout,
        payoutMethod,
        payoutDestination,
        status: 'pending_admin',
        payoutChannel: 'manual',
        timestamp: FieldValue.serverTimestamp(),
        requestedByCloudFunction: true,
        reservedCreditIds: ledger.reservedCreditIds,
        omiseDebit: ledger.omiseDebit,
        creditDebit: ledger.creditDebit,
      });

      return {
        withdrawRequestId: withdrawRef.id,
        amount,
        withdrawFeeBaht,
        netPayout,
        payoutMethod,
      };
    });

    logger.info('manual withdraw requested', {
      uid,
      actorType,
      amount,
      withdrawFeeBaht,
      netPayout,
      payoutMethod,
      withdrawRequestId: reservation.withdrawRequestId,
    });

    return {
      success: true,
      ...reservation,
      status: 'pending_admin',
    };
  });

  const exportWithdrawBankCsv = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
    await assertVan4Admin(request);

    const requestIds = Array.isArray(request.data?.requestIds)
      ? request.data.requestIds.map((value) => String(value || '').trim()).filter(Boolean)
      : [];

    let snapshot;
    if (requestIds.length > 0) {
      const docs = await Promise.all(
        requestIds.map((id) => db.collection('withdraw_requests').doc(id).get()),
      );
      snapshot = {
        docs: docs.filter((doc) => {
          if (!doc.exists || String(doc.data()?.status || '') !== 'pending_admin') {
            return false;
          }
          const destination = doc.data()?.payoutDestination || {};
          return Boolean(
            destination.accountNumber ||
              (String(doc.data()?.payoutMethod || '') === 'bank' &&
                destination.bankName),
          );
        }),
      };
    } else {
      snapshot = await db
        .collection('withdraw_requests')
        .where('status', '==', 'pending_admin')
        .get();
      snapshot = {
        docs: snapshot.docs.filter((doc) => {
          const destination = doc.data()?.payoutDestination || {};
          return Boolean(destination.accountNumber);
        }),
      };
    }

    if (snapshot.docs.length === 0) {
      throw new HttpsError('not-found', 'ไม่มีคำขอถอนธนาคารที่รอดำเนินการ');
    }

    const batchExportId = `batch_${Date.now()}`;
    const lines = [
      'payout_type,request_id,recipient_name,bank_name,account_number,account_name,amount,actor_type,uid,requested_at',
    ];

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const destination = data.payoutDestination || {};
      lines.push(
        [
          csvCell('withdraw'),
          csvCell(doc.id),
          csvCell(destination.accountName || data.uid),
          csvCell(destination.bankName || ''),
          csvCell(destination.accountNumber || ''),
          csvCell(destination.accountName || ''),
          csvCell(readMoney(data.netPayout ?? resolveNetPayout(data)).toFixed(2)),
          csvCell(data.actorType || ''),
          csvCell(data.uid || ''),
          csvCell(formatCsvTimestamp(data.timestamp)),
        ].join(','),
      );
      batch.set(
        doc.ref,
        {
          batchExportId,
          exportedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();

    return {
      success: true,
      batchExportId,
      rowCount: snapshot.docs.length,
      csv: lines.join('\n'),
    };
  });

  const rejectManualWithdraw = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
    await assertVan4Admin(request);

    const withdrawRequestId = String(request.data?.withdrawRequestId || '').trim();
    const reason = String(request.data?.reason || 'ปฏิเสธโดยแอดมิน').trim();
    if (!withdrawRequestId) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ withdrawRequestId');
    }

    const withdrawDoc = await db.collection('withdraw_requests').doc(withdrawRequestId).get();
    if (!withdrawDoc.exists) {
      throw new HttpsError('not-found', 'ไม่พบคำขอถอนเงิน');
    }

    const rejectData = withdrawDoc.data() || {};
    await assertAdminBranchAccess(request, await resolveMerchantBranchId(rejectData.uid));

    const status = String(rejectData.status || '').trim();
    if (status !== 'pending_admin') {
      throw new HttpsError('failed-precondition', 'คำขอนี้ไม่อยู่ในสถานะรอแอดมิน');
    }

    await withdrawDoc.ref.set(
      {
        failureMessage: reason,
        rejectedAt: FieldValue.serverTimestamp(),
        rejectedBy: request.auth.uid,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await rollbackWithdrawReservation(withdrawDoc);

    return { success: true, withdrawRequestId, status: 'failed' };
  });

  const confirmManualWithdraw = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
      secrets: [SLIPOK_API_KEY_SECRET],
    },
    async (request) => {
      await assertVan4Admin(request);

      const withdrawRequestId = String(request.data?.withdrawRequestId || '').trim();
      const storagePath = String(request.data?.storagePath || '').trim();
      const fileName = String(request.data?.fileName || 'withdraw-slip.jpg').trim();
      const contentType = String(request.data?.contentType || 'image/jpeg').trim();

      if (!withdrawRequestId || !storagePath) {
        throw new HttpsError('invalid-argument', 'กรุณาระบุ withdrawRequestId และ storagePath');
      }

      const withdrawDoc = await db.collection('withdraw_requests').doc(withdrawRequestId).get();
      if (!withdrawDoc.exists) {
        throw new HttpsError('not-found', 'ไม่พบคำขอถอนเงิน');
      }

      const data = withdrawDoc.data() || {};
      const merchantBranchId = await resolveMerchantBranchId(data.uid);
      await assertAdminBranchAccess(request, merchantBranchId);
      const status = String(data.status || '').trim();
      if (status !== 'pending_admin') {
        throw new HttpsError('failed-precondition', 'คำขอนี้ไม่อยู่ในสถานะรอแอดมิน');
      }

      const amount = readMoney(data.amount);
      const withdrawFeeBaht = readMoney(data.withdrawFeeBaht);
      const netPayout = resolveNetPayout(data);
      const adminPayoutMethod = String(
        request.data?.adminPayoutMethod || data.payoutMethod || '',
      )
        .trim()
        .toLowerCase();
      const payoutDestination = data.payoutDestination || {};

      if (adminPayoutMethod !== 'promptpay' && adminPayoutMethod !== 'bank') {
        throw new HttpsError(
          'invalid-argument',
          'กรุณาระบุช่องทางที่แอดมินใช้โอน (promptpay หรือ bank)',
        );
      }
      if (adminPayoutMethod === 'promptpay' && !payoutDestination.promptPayId) {
        throw new HttpsError('failed-precondition', 'คำขอนี้ไม่มี PromptPay ในระบบ');
      }
      if (adminPayoutMethod === 'bank' && !payoutDestination.accountNumber) {
        throw new HttpsError('failed-precondition', 'คำขอนี้ไม่มีบัญชีธนาคารในระบบ');
      }

      const verification = await verifyStandaloneSlipCore({
        admin,
        db,
        FieldValue,
        logger,
        SLIPOK_API_KEY_SECRET,
        ...slipVerificationDeps,
        customerUid: String(data.uid || '').trim(),
        storagePath,
        paymentGroupId: withdrawRequestId,
        fileName,
        contentType,
        expectedCombinedAmount: netPayout,
        validateSlipReceiver: (providerPayload) =>
          validateWithdrawSlipReceiver(
            providerPayload,
            payoutDestination,
            adminPayoutMethod,
          ),
        buildSlipVerificationMessage: (verifyStatus, providerPayload, fallbackMessage) => {
          if (verifyStatus === 'verified') {
            return 'ยืนยันการโอนเงินถอนสำเร็จ';
          }
          return slipVerificationDeps.buildSlipVerificationMessage(
            verifyStatus,
            providerPayload,
            fallbackMessage,
          );
        },
      });

      if (verification.status !== 'verified') {
        throw new HttpsError(
          'failed-precondition',
          verification.message || 'สลิปไม่ผ่านการตรวจสอบ',
        );
      }

      await withdrawDoc.ref.set(
        {
          adminPayoutMethod,
          slipStoragePath: storagePath,
          slipVerifiedAt: FieldValue.serverTimestamp(),
          slipVerifiedBy: request.auth.uid,
          slipVerification: verification,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await finalizeWithdrawPaid(withdrawDoc, { paid: true, status: 'paid' });

      return {
        success: true,
        withdrawRequestId,
        status: 'paid',
        amount,
        withdrawFeeBaht,
        netPayout,
      };
    },
  );

  const getWithdrawableBalance = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const uid = String(request.auth.uid).trim();
    const actorType = String(request.data?.actorType || 'rider').trim();
    if (actorType !== 'rider' && actorType !== 'merchant') {
      throw new HttpsError('invalid-argument', 'actorType ไม่ถูกต้อง');
    }

    const [balance, profileResult, configResult] = await Promise.all([
      computeWithdrawableBalance(uid, actorType),
      loadPayoutProfile(uid, actorType).catch(() => null),
      loadSettlementConfig().catch(() => null),
    ]);

    let bankLabel = null;
    let accountName = null;
    let promptPayLabel = null;
    let hasBankProfile = false;
    let hasPromptPayProfile = false;

    if (profileResult) {
      const profile = profileResult;
      hasBankProfile = hasValidBankProfile(profile);
      hasPromptPayProfile = hasValidPromptPayProfile(profile);
      if (hasBankProfile) {
        bankLabel = `${profile.bankName} ${maskAccountNumber(profile.accountNumber)}`;
        accountName = profile.accountName || null;
      }
      if (hasPromptPayProfile) {
        promptPayLabel = `PromptPay ${maskPromptPayId(resolvePromptPayId(profile))}`;
      }
    }

    const withdrawBankCsvThreshold =
      configResult?.withdrawBankCsvThreshold ?? 5;
    const withdrawFeeBaht = resolveWithdrawFeeBaht(configResult);
    const minGrossWithdrawAmount = roundMoney(MIN_WITHDRAW_BAHT + withdrawFeeBaht);

    return {
      uid,
      actorType,
      ...balance,
      minWithdrawAmount: MIN_WITHDRAW_BAHT,
      minGrossWithdrawAmount,
      withdrawFeeBaht,
      bankLabel,
      accountName,
      promptPayLabel,
      hasBankProfile,
      hasPromptPayProfile,
      hasPayoutProfile: hasBankProfile || hasPromptPayProfile,
      withdrawBankCsvThreshold,
    };
  });

  return {
    getWithdrawableBalance,
    requestManualWithdraw,
    exportWithdrawBankCsv,
    confirmManualWithdraw,
    rejectManualWithdraw,
  };
}

module.exports = {
  createManualPayoutHandlers,
  validateWithdrawSlipReceiver,
};
