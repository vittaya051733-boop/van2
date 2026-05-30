/**
 * Live Firestore smoke test against production (rules enforced).
 * Requires ADC (gcloud auth application-default login) or GOOGLE_APPLICATION_CREDENTIALS
 * and scripts/smoke-test-config.local.json with riderUid (+ optional customerUid, shopUid).
 */
const { readFileSync, existsSync } = require('fs');
const { join } = require('path');
const admin = require('firebase-admin');

const CONFIG_PATH = join(__dirname, '..', 'smoke-test-config.local.json');
const DEFAULT_API_KEY = 'AIzaSyB6Q5DE_VkpqO3qTn3bqPBawQjxzGEngxY';

function loadConfig() {
  if (!existsSync(CONFIG_PATH)) {
    return null;
  }
  return JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
}

async function signInWithCustomToken(apiKey, customToken) {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body.error?.message || `Auth failed (${response.status})`);
  }
  return body.idToken;
}

async function runQuery(idToken, projectId, structuredQuery) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ structuredQuery }),
  });
  const body = await response.json();
  if (!response.ok) {
    const message = body.error?.message || JSON.stringify(body);
    if (message.includes('PERMISSION_DENIED') || message.includes('Missing or insufficient permissions')) {
      throw new Error(`PERMISSION_DENIED: ${message}`);
    }
    throw new Error(message);
  }
  return body;
}

async function getDocument(idToken, projectId, path) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const body = await response.json();
  if (!response.ok) {
    const message = body.error?.message || JSON.stringify(body);
    if (message.includes('PERMISSION_DENIED') || message.includes('Missing or insufficient permissions')) {
      throw new Error(`PERMISSION_DENIED: ${message}`);
    }
    throw new Error(message);
  }
  return body;
}

async function testAsUid(projectId, apiKey, uid, checks) {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }
  const customToken = await admin.auth().createCustomToken(uid);
  const idToken = await signInWithCustomToken(apiKey, customToken);

  for (const check of checks) {
    if (check.type === 'query') {
      await runQuery(idToken, projectId, check.structuredQuery);
      console.log(`PASS live: ${check.label}`);
    } else if (check.type === 'get') {
      await getDocument(idToken, projectId, check.path);
      console.log(`PASS live: ${check.label}`);
    }
  }
}

async function run() {
  const config = loadConfig();
  if (!config) {
    console.log('SKIP live-firestore: no smoke-test-config.local.json (rules emulator test still runs)');
    return;
  }

  const projectId = config.projectId || 'van-merchant';
  const apiKey = config.webApiKey || DEFAULT_API_KEY;
  const riderUid = config.riderUid?.trim();
  if (!riderUid) {
    console.log('SKIP live-firestore: riderUid not set in config');
    return;
  }

  await testAsUid(projectId, apiKey, riderUid, [
    {
      type: 'query',
      label: `van3 rider orders query (uid=${riderUid})`,
      structuredQuery: {
        from: [{ collectionId: 'orders' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'driverId' },
            op: 'EQUAL',
            value: { stringValue: riderUid },
          },
        },
        limit: 1,
      },
    },
    {
      type: 'get',
      label: `van3 rider profile riders/${riderUid}`,
      path: `riders/${riderUid}`,
    },
  ]);

  const customerUid = config.customerUid?.trim();
  if (customerUid) {
    await testAsUid(projectId, apiKey, customerUid, [
      {
        type: 'get',
        label: `van2 customer_users/${customerUid}`,
        path: `customer_users/${customerUid}`,
      },
    ]);
  }

  const shopUid = config.shopUid?.trim();
  if (shopUid) {
    await testAsUid(projectId, apiKey, shopUid, [
      {
        type: 'query',
        label: `van1 shop orders query (shopOwnerId=${shopUid})`,
        structuredQuery: {
          from: [{ collectionId: 'orders' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'shopOwnerId' },
              op: 'EQUAL',
              value: { stringValue: shopUid },
            },
          },
          limit: 1,
        },
      },
    ]);
  }

  console.log('PASS live-firestore: production rules allow key reads');
}

run().catch((error) => {
  console.error('FAIL live-firestore:', error.message || error);
  process.exit(1);
});
