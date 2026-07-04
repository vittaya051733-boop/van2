const crypto = require('crypto');
const { COLLECTIONS, OAUTH_STATE_TTL_MS } = require('./constants');
const { getVan4Firestore } = require('./db');

function signOAuthState(payload, secret) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto
    .createHmac('sha256', secret)
    .update(body)
    .digest('base64url');
  return `${body}.${sig}`;
}

function verifyOAuthState(state, secret) {
  const parts = String(state || '').split('.');
  if (parts.length !== 2) {
    return null;
  }
  const [body, sig] = parts;
  const expected = crypto
    .createHmac('sha256', secret)
    .update(body)
    .digest('base64url');
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
    return null;
  }
  try {
    return JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
}

async function storeOAuthState(stateId, data) {
  const db = getVan4Firestore();
  await db.collection(COLLECTIONS.OAUTH_STATES).doc(stateId).set({
    ...data,
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + OAUTH_STATE_TTL_MS),
  });
}

async function consumeOAuthState(stateId) {
  const db = getVan4Firestore();
  const ref = db.collection(COLLECTIONS.OAUTH_STATES).doc(stateId);
  const snap = await ref.get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() || {};
  const expiresAt = data.expiresAt?.toDate?.() || new Date(0);
  await ref.delete();
  if (expiresAt.getTime() < Date.now()) {
    return null;
  }
  return data;
}

async function saveAccountSecrets(accountId, secrets) {
  const db = getVan4Firestore();
  await db.collection(COLLECTIONS.ACCOUNT_SECRETS).doc(accountId).set(
    {
      ...secrets,
      updatedAt: new Date(),
    },
    { merge: true },
  );
}

async function loadAccountSecrets(accountId) {
  const db = getVan4Firestore();
  const snap = await db
    .collection(COLLECTIONS.ACCOUNT_SECRETS)
    .doc(accountId)
    .get();
  if (!snap.exists) {
    return null;
  }
  return snap.data();
}

async function deleteAccountSecrets(accountId) {
  const db = getVan4Firestore();
  await db.collection(COLLECTIONS.ACCOUNT_SECRETS).doc(accountId).delete();
}

module.exports = {
  signOAuthState,
  verifyOAuthState,
  storeOAuthState,
  consumeOAuthState,
  saveAccountSecrets,
  loadAccountSecrets,
  deleteAccountSecrets,
};
