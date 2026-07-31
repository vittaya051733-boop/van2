const SLIP_VERIFICATION_JOBS_COLLECTION = 'slip_verification_jobs';
const JOB_POLL_INTERVAL_MS = 500;
const JOB_WAIT_TIMEOUT_MS = 55 * 1000;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForSlipVerificationJob(db, jobId, timeoutMs = JOB_WAIT_TIMEOUT_MS) {
  const ref = db.collection(SLIP_VERIFICATION_JOBS_COLLECTION).doc(jobId);
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const snapshot = await ref.get();
    const data = snapshot.data();
    const status = String(data?.status || '').trim();
    if (status === 'completed' || status === 'failed') {
      return data?.result || null;
    }
    await sleep(JOB_POLL_INTERVAL_MS);
  }

  return null;
}

function createSlipVerificationQueueHandlers({
  admin,
  db,
  FieldValue,
  logger,
  HttpsError,
  onCall,
  onDocumentCreated,
  DEFAULT_REGION,
  SLIPOK_API_KEY_SECRET,
  verifyStandaloneSlipCore,
  deps,
}) {
  async function enqueueStandaloneSlipVerification(request) {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนส่งสลิป');
    }

    const storagePath = String(request.data?.storagePath || '').trim();
    const paymentGroupId = String(request.data?.paymentGroupId || '').trim();
    const fileName = String(request.data?.fileName || 'slip.jpg').trim() || 'slip.jpg';
    const contentType = String(request.data?.contentType || 'image/jpeg').trim() || 'image/jpeg';
    const expectedCombinedAmount = deps.parseNumber(request.data?.expectedAmount);

    if (!storagePath) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ storagePath');
    }
    if (!Number.isFinite(expectedCombinedAmount) || expectedCombinedAmount <= 0) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุยอดที่ต้องตรวจสลิป');
    }

    const jobRef = db.collection(SLIP_VERIFICATION_JOBS_COLLECTION).doc();
    await jobRef.set({
      kind: 'standalone',
      status: 'queued',
      customerUid: request.auth.uid,
      storagePath,
      paymentGroupId,
      fileName,
      contentType,
      expectedCombinedAmount,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const result = await waitForSlipVerificationJob(db, jobRef.id);
    if (!result) {
      throw new HttpsError(
        'deadline-exceeded',
        'ระบบตรวจสลิปใช้เวลานานกว่าปกติ กรุณาลองใหม่อีกครั้ง',
      );
    }

    return result;
  }

  const verifyStandalonePaymentSlip = onCall(
    {
      region: DEFAULT_REGION,
      secrets: [SLIPOK_API_KEY_SECRET],
    },
    enqueueStandaloneSlipVerification,
  );

  const processSlipVerificationJob = onDocumentCreated(
    {
      document: `${SLIP_VERIFICATION_JOBS_COLLECTION}/{jobId}`,
      region: DEFAULT_REGION,
      secrets: [SLIPOK_API_KEY_SECRET],
      maxInstances: 50,
      timeoutSeconds: 120,
    },
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        return;
      }

      const jobId = event.params.jobId;
      const jobRef = snapshot.ref;
      const job = snapshot.data() || {};
      if (String(job.status || '') !== 'queued') {
        return;
      }

      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(jobRef);
        const currentData = current.data() || {};
        if (String(currentData.status || '') !== 'queued') {
          return false;
        }
        transaction.update(jobRef, {
          status: 'processing',
          updatedAt: FieldValue.serverTimestamp(),
          processingStartedAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) {
        return;
      }

      try {
        const result = await verifyStandaloneSlipCore({
          admin,
          db,
          FieldValue,
          logger,
          SLIPOK_API_KEY_SECRET,
          customerUid: String(job.customerUid || '').trim(),
          storagePath: String(job.storagePath || '').trim(),
          paymentGroupId: String(job.paymentGroupId || '').trim(),
          fileName: String(job.fileName || 'slip.jpg').trim() || 'slip.jpg',
          contentType: String(job.contentType || 'image/jpeg').trim() || 'image/jpeg',
          expectedCombinedAmount: deps.parseNumber(job.expectedCombinedAmount),
          ...deps,
        });

        await jobRef.update({
          status: 'completed',
          result,
          updatedAt: FieldValue.serverTimestamp(),
          completedAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        logger.error('processSlipVerificationJob failed', {
          jobId,
          message: error instanceof Error ? error.message : String(error),
        });
        await jobRef.update({
          status: 'failed',
          result: {
            success: false,
            status: 'error',
            message: error instanceof Error ? error.message : 'ส่งสลิปไปตรวจสอบไม่สำเร็จ',
            expectedCombinedAmount: deps.parseNumber(job.expectedCombinedAmount),
            paymentGroupId: String(job.paymentGroupId || '').trim(),
            storagePath: String(job.storagePath || '').trim(),
          },
          updatedAt: FieldValue.serverTimestamp(),
          completedAt: FieldValue.serverTimestamp(),
        });
      }
    },
  );

  return {
    verifyStandalonePaymentSlip,
    processSlipVerificationJob,
  };
}

module.exports = {
  SLIP_VERIFICATION_JOBS_COLLECTION,
  createSlipVerificationQueueHandlers,
};
