const { HttpsError } = require('firebase-functions/v2/https');

let db;

function init(deps) {
  db = deps.db;
}

function resolveRiderRegistrationStatus(registrationData, riderData) {
  if (registrationData && typeof registrationData === 'object') {
    return String(registrationData.registrationStatus || '').trim().toLowerCase();
  }
  if (riderData && typeof riderData === 'object') {
    return String(riderData.registrationStatus || '').trim().toLowerCase();
  }
  return '';
}

async function assertApprovedRider(tx, uid) {
  const trimmedUid = String(uid || '').trim();
  if (!trimmedUid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
  }

  const [registrationSnap, riderSnap] = await Promise.all([
    tx.get(db.collection('rider_registrations').doc(trimmedUid)),
    tx.get(db.collection('riders').doc(trimmedUid)),
  ]);

  const registrationStatus = resolveRiderRegistrationStatus(
    registrationSnap.exists ? registrationSnap.data() : null,
    riderSnap.exists ? riderSnap.data() : null,
  );

  if (registrationStatus === 'approved') {
    return;
  }
  if (registrationStatus === 'rejected') {
    throw new HttpsError('permission-denied', 'บัญชีไรเดอร์ถูกปฏิเสธ ไม่สามารถดำเนินการได้');
  }
  if (registrationStatus === 'pending') {
    throw new HttpsError('permission-denied', 'บัญชีไรเดอร์ยังไม่ได้รับการอนุมัติ');
  }
  if (!registrationSnap.exists && !riderSnap.exists) {
    throw new HttpsError('permission-denied', 'ไม่พบข้อมูลไรเดอร์');
  }
  throw new HttpsError('permission-denied', 'บัญชีไรเดอร์ยังไม่ได้รับการอนุมัติ');
}

async function assertApprovedRiderOutsideTransaction(uid) {
  return db.runTransaction(async (tx) => assertApprovedRider(tx, uid));
}

module.exports = {
  init,
  assertApprovedRider,
  assertApprovedRiderOutsideTransaction,
  resolveRiderRegistrationStatus,
};
