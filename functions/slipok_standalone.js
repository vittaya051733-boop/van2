async function verifyStandaloneSlipCore({
  admin,
  db,
  FieldValue,
  logger,
  readRequiredConfiguredSecret,
  getPaymentCollectionSettings,
  buildSlipVerificationMessage,
  amountsMatch,
  validateSlipReceiver,
  buildExpectedReceiverTargets,
  writeSlipOkFeedbackLog,
  parseNumber,
  SLIPOK_API_KEY_SECRET,
  SLIPOK_ENDPOINT,
  customerUid,
  storagePath,
  paymentGroupId,
  fileName,
  contentType,
  expectedCombinedAmount,
}) {
  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    const error = new Error('ไม่พบไฟล์สลิปใน Firebase Storage');
    error.code = 'not-found';
    throw error;
  }

  const paymentCollectionSettings = await getPaymentCollectionSettings();

  let verificationStatus = 'error';
  let verificationMessage = 'ส่งสลิปไปตรวจไม่สำเร็จ';
  let responseCode = 0;
  let providerPayload = null;
  let verifiedSlipAmount = null;
  let providerRawText = '';

  try {
    const [buffer] = await file.download();
    const apiKey = readRequiredConfiguredSecret(
      SLIPOK_API_KEY_SECRET,
      'SLIPOK_API_KEY',
      'ระบบตรวจสลิป Slip OK',
    );

    const formData = new FormData();
    formData.append('files', new Blob([buffer], { type: contentType }), fileName);
    formData.append('log', 'true');
    formData.append('amount', expectedCombinedAmount.toString());

    const slipResponse = await fetch(SLIPOK_ENDPOINT, {
      method: 'POST',
      headers: {
        'x-authorization': apiKey,
      },
      body: formData,
    });

    responseCode = slipResponse.status;
    providerRawText = await slipResponse.text();
    try {
      providerPayload = providerRawText ? JSON.parse(providerRawText) : null;
    } catch (_) {
      providerPayload = { raw: providerRawText };
    }

    const requestSucceeded = providerPayload?.success === true;
    const dataSucceeded = providerPayload?.data?.success === true;
    verifiedSlipAmount = parseNumber(providerPayload?.data?.amount);
    const hasMatchingAmount = amountsMatch(verifiedSlipAmount, expectedCombinedAmount);
    const receiverValidation = validateSlipReceiver(providerPayload, paymentCollectionSettings);
    const hasMatchingReceiver = receiverValidation.matched;

    if (
      slipResponse.ok &&
      requestSucceeded &&
      dataSucceeded &&
      hasMatchingAmount &&
      hasMatchingReceiver
    ) {
      verificationStatus = 'verified';
      verificationMessage = buildSlipVerificationMessage(
        verificationStatus,
        providerPayload,
        'ตรวจสอบสลิปสำเร็จ',
      );
    } else if (slipResponse.ok && requestSucceeded && dataSucceeded && !hasMatchingAmount) {
      verificationStatus = 'failed';
      providerPayload = {
        ...(providerPayload && typeof providerPayload === 'object' ? providerPayload : {}),
        code: Number(providerPayload?.code) || 1013,
        data: {
          ...(providerPayload?.data && typeof providerPayload.data === 'object'
            ? providerPayload.data
            : {}),
          amount: Number.isFinite(verifiedSlipAmount)
            ? verifiedSlipAmount
            : providerPayload?.data?.amount,
          expectedAmount: expectedCombinedAmount,
          message:
            providerPayload?.data?.message || 'ยอดที่ส่งมาไม่ตรงกับยอดสลิป',
        },
        message: providerPayload?.message || 'ยอดที่ส่งมาไม่ตรงกับยอดสลิป',
      };
      verificationMessage = buildSlipVerificationMessage(
        verificationStatus,
        providerPayload,
        'ยอดเงินในสลิปไม่ตรงกับยอดที่ต้องชำระ',
      );
    } else if (slipResponse.ok && requestSucceeded && dataSucceeded && !hasMatchingReceiver) {
      verificationStatus = 'failed';
      providerPayload = {
        ...(providerPayload && typeof providerPayload === 'object' ? providerPayload : {}),
        code: Number(providerPayload?.code) || 1014,
        data: {
          ...(providerPayload?.data && typeof providerPayload.data === 'object'
            ? providerPayload.data
            : {}),
          receiverValidation,
          expectedRecipientDisplayName: paymentCollectionSettings.recipientDisplayName,
          expectedReceiverTargets: buildExpectedReceiverTargets(paymentCollectionSettings),
          message:
            providerPayload?.data?.message || 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
        },
        message: providerPayload?.message || 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
      };
      verificationMessage = buildSlipVerificationMessage(
        verificationStatus,
        providerPayload,
        'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
      );
    } else {
      verificationStatus = 'failed';
      verificationMessage = buildSlipVerificationMessage(
        verificationStatus,
        providerPayload,
        `Slip OK responded with status ${slipResponse.status}`,
      );
    }
  } catch (error) {
    verificationStatus = 'error';
    providerPayload = {
      message: error instanceof Error ? error.message : String(error),
    };
    verificationMessage = buildSlipVerificationMessage(
      verificationStatus,
      providerPayload,
      'ส่งสลิปไปตรวจสอบไม่สำเร็จ',
    );
    logger.error('verifyStandaloneSlipCore failed', {
      paymentGroupId,
      storagePath,
      message: verificationMessage,
    });
  }

  const slipOkFeedbackId = await writeSlipOkFeedbackLog({
    feedbackId: paymentGroupId,
    customerUid,
    orderIds: [],
    paymentGroupId,
    storagePath,
    fileName,
    contentType,
    expectedCombinedAmount,
    verifiedSlipAmount,
    verificationStatus,
    verificationMessage,
    responseCode,
    providerPayload,
    providerRawText,
  });

  return {
    success: verificationStatus === 'verified',
    status: verificationStatus,
    message: verificationMessage,
    expectedCombinedAmount,
    verifiedSlipAmount,
    feedbackId: slipOkFeedbackId,
    paymentGroupId,
    storagePath,
  };
}

module.exports = {
  verifyStandaloneSlipCore,
};
