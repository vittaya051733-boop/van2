const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

function normalizeBranchId(raw) {
  const value = String(raw || '').trim();
  if (!value) return 'central';
  if (value === 'nonsung') return 'central';
  return value;
}

async function loadAdminProfile(auth) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'ต้องล็อกอินก่อน');
  }

  const email = String(auth.token?.email || '').trim().toLowerCase();
  if (!email) {
    throw new HttpsError('permission-denied', 'บัญชีแอดมินต้องมีอีเมล');
  }

  const doc = await admin.firestore().collection('admins').doc(email).get();
  if (!doc.exists || doc.data()?.active === false) {
    throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์แอดมิน');
  }

  const data = doc.data() || {};
  const role = String(data.role || 'super_admin').trim().toLowerCase();
  const branchId = data.branchId ? normalizeBranchId(data.branchId) : null;

  return {
    uid: auth.uid,
    email,
    role,
    branchId,
    isSuperAdmin: role !== 'branch_admin',
    isBranchAdmin: role === 'branch_admin',
    displayName: String(data.displayName || email).trim(),
  };
}

async function assertVan4Admin(request) {
  return loadAdminProfile(request.auth);
}

async function assertSuperAdmin(request) {
  const profile = await loadAdminProfile(request.auth);
  if (!profile.isSuperAdmin) {
    throw new HttpsError('permission-denied', 'ต้องเป็น super admin');
  }
  return profile;
}

async function assertAdminBranchAccess(request, resourceBranchId) {
  const profile = await loadAdminProfile(request.auth);
  if (profile.isSuperAdmin) {
    return profile;
  }
  const normalized = normalizeBranchId(resourceBranchId);
  if (profile.branchId !== normalized) {
    throw new HttpsError('permission-denied', 'branch_scope');
  }
  return profile;
}

async function resolveMerchantBranchId(uid) {
  const ownerId = String(uid || '').trim();
  if (!ownerId) {
    return 'central';
  }

  try {
    const pub = await admin.firestore().collection('public_shops').doc(ownerId).get();
    if (pub.exists) {
      return normalizeBranchId(pub.data()?.branchId || pub.data()?.marketId);
    }
  } catch (_) {}

  const collections = [
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
  ];
  for (const collection of collections) {
    try {
      const snap = await admin.firestore().collection(collection).doc(ownerId).get();
      if (snap.exists) {
        return normalizeBranchId(snap.data()?.branchId || snap.data()?.marketId);
      }
    } catch (_) {}
  }

  return 'central';
}

module.exports = {
  normalizeBranchId,
  loadAdminProfile,
  assertVan4Admin,
  assertSuperAdmin,
  assertAdminBranchAccess,
  resolveMerchantBranchId,
};
