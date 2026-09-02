const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { assertSuperAdmin, normalizeBranchId } = require('./social/admin_guard');

const DEFAULT_REGION = 'asia-southeast1';

function registerAdminProvisionHandlers() {
  const adminProvisionBranchAdmin = onCall(
    { region: DEFAULT_REGION, enforceAppCheck: true },
    async (request) => {
      const caller = await assertSuperAdmin(request);

      const email = String(request.data?.email || '').trim().toLowerCase();
      const displayName = String(request.data?.displayName || email).trim();
      const branchId = normalizeBranchId(request.data?.branchId);
      const authUid = String(request.data?.authUid || '').trim();

      if (!email || !email.includes('@')) {
        throw new HttpsError('invalid-argument', 'ต้องมี email ที่ถูกต้อง');
      }
      if (!branchId) {
        throw new HttpsError('invalid-argument', 'ต้องมี branchId');
      }

      const branchSnap = await admin.firestore().collection('branches').doc(branchId).get();
      if (!branchSnap.exists) {
        throw new HttpsError('failed-precondition', `ไม่พบ branches/${branchId}`);
      }

      await admin.firestore().collection('admins').doc(email).set(
        {
          email,
          displayName,
          active: true,
          role: 'branch_admin',
          branchId,
          ...(authUid ? { authUid } : {}),
          provisionedBy: caller.email,
          provisionedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return {
        ok: true,
        email,
        branchId,
        role: 'branch_admin',
      };
    },
  );

  return { adminProvisionBranchAdmin };
}

module.exports = {
  registerAdminProvisionHandlers,
};
