const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

async function assertVan4Admin(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'ต้องล็อกอินก่อน');
  }

  const email = String(request.auth.token.email || '')
    .trim()
    .toLowerCase();
  if (!email) {
    throw new HttpsError('permission-denied', 'บัญชีแอดมินต้องมีอีเมล');
  }

  const doc = await admin
    .firestore()
    .collection('admins')
    .doc(email)
    .get();

  if (!doc.exists || doc.data()?.active === false) {
    throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์แอดมิน');
  }

  return {
    uid: request.auth.uid,
    email,
  };
}

module.exports = {
  assertVan4Admin,
};
