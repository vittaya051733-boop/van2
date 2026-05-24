/**
 * สร้างแอดมิน van4: Firebase Auth (รหัสผ่าน) + Firestore collection admins (allowlist)
 *
 * รหัสผ่านเก็บใน Firebase Auth เท่านั้น — ไม่เขียนลง Firestore (ปลอดภัย)
 *
 * Usage:
 *   node scripts/seed-admin.mjs --email admin@example.com --password "YourSecurePass123"
 *   node scripts/seed-admin.mjs --email existing@example.com   # เพิ่ม allowlist อย่างเดียว
 *
 * Requires Application Default Credentials:
 *   gcloud auth application-default login
 *   OR set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON path
 */
import { createRequire } from 'node:module';
import { parseArgs } from 'node:util';

const require = createRequire(import.meta.url);
const admin = require('../functions/node_modules/firebase-admin');

const { values } = parseArgs({
  options: {
    email: { type: 'string' },
    password: { type: 'string' },
    name: { type: 'string' },
    project: { type: 'string', default: 'van-merchant' },
    'force-password': { type: 'boolean', default: false },
  },
});

const email = values.email?.trim().toLowerCase();
const password = values.password;
const displayName = values.name?.trim() || 'Van Market Admin';
const projectId = values.project;
const forcePassword = values['force-password'] === true;

if (!email || !email.includes('@')) {
  console.error('Provide --email admin@example.com');
  process.exit(1);
}

admin.initializeApp({ projectId });

const auth = admin.auth();
const db = admin.firestore();
const adminCollection = 'admins';

let authUser;
try {
  authUser = await auth.getUserByEmail(email);
  console.log(`Auth user exists: ${authUser.uid}`);
  if (password) {
    if (!forcePassword) {
      console.log('Keeping existing Auth password (use --force-password to change).');
      await auth.updateUser(authUser.uid, { displayName, emailVerified: true });
    } else {
      if (password.length < 8) {
        console.error('Password must be at least 8 characters.');
        process.exit(1);
      }
      await auth.updateUser(authUser.uid, { password, displayName, emailVerified: true });
      console.log('Updated password in Firebase Auth.');
    }
  } else {
    await auth.updateUser(authUser.uid, { displayName, emailVerified: true });
    console.log('Linked existing Auth user without changing password.');
  }
} catch (error) {
  if (error.code !== 'auth/user-not-found') {
    throw error;
  }
  if (!password || password.length < 8) {
    console.error('New Auth user requires --password (min 8 characters).');
    process.exit(1);
  }
  authUser = await auth.createUser({
    email,
    password,
    displayName,
    emailVerified: true,
  });
  console.log(`Created Auth user: ${authUser.uid}`);
}

await db.collection(adminCollection).doc(email).set(
  {
    email,
    active: true,
    displayName,
    authUid: authUser.uid,
    passwordManagedBy: 'firebase_auth',
    hasPasswordSet: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  },
  { merge: true },
);

console.log(`Firestore doc admins/${email} ready.`);
console.log('Done. Sign in to van4 with this email and your Firebase Auth password.');
