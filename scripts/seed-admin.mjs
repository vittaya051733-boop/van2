/**
 * Seed admins/{email} (+ optional Firebase Auth user) in one shot.
 *
 * Examples:
 *   node scripts/seed-admin.mjs --email manager@example.com --password "TempPass123!" --name "ผู้จัดการสาขาอุดร" --role branch_admin --branch-id udon_north
 *   node scripts/seed-admin.mjs --email boss@example.com --password "TempPass123!" --role super_admin
 *   node scripts/seed-admin.mjs --email manager@example.com --firestore-only --role branch_admin --branch-id udon_north
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

function readArg(name) {
  const prefix = `--${name}=`;
  const hit = process.argv.find((arg) => arg.startsWith(prefix));
  if (hit) return hit.slice(prefix.length);

  const flag = `--${name}`;
  const index = process.argv.indexOf(flag);
  if (index >= 0 && index + 1 < process.argv.length) {
    const next = process.argv[index + 1];
    if (!next.startsWith('--')) return next;
  }
  return null;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function usage() {
  console.log(`
Usage:
  node scripts/seed-admin.mjs --email <email> [options]

Options:
  --password=<pwd>       Create/update Firebase Auth user (required unless --firestore-only)
  --name=<displayName>   Display name (default: part before @ in email)
  --role=<role>          super_admin | branch_admin (default: branch_admin)
  --branch-id=<id>       Required when role=branch_admin
  --project=<id>         Firebase project (default: van-merchant)
  --firestore-only       Skip Auth; only write admins/{email}
  --dry-run              Print payload only
`);
}

async function main() {
  const email = String(readArg('email') || '').trim().toLowerCase();
  const password = readArg('password');
  const displayName = String(readArg('name') || email.split('@')[0] || 'Admin').trim();
  const role = String(readArg('role') || 'branch_admin').trim().toLowerCase();
  const branchId = String(readArg('branch-id') || '').trim();
  const projectId = String(readArg('project') || 'van-merchant').trim();
  const firestoreOnly = hasFlag('firestore-only');
  const dryRun = hasFlag('dry-run');

  if (!email || !email.includes('@')) {
    usage();
    throw new Error('ต้องระบุ --email ที่ถูกต้อง');
  }
  if (role === 'branch_admin' && !branchId) {
    throw new Error('role=branch_admin ต้องมี --branch-id');
  }
  if (!firestoreOnly && !password) {
    throw new Error('ต้องมี --password หรือใช้ --firestore-only');
  }

  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  if (role === 'branch_admin') {
    const branchSnap = await db.collection('branches').doc(branchId).get();
    if (!branchSnap.exists) {
      throw new Error(`ไม่พบ branches/${branchId} — สร้างสาขาก่อน`);
    }
  }

  const adminDoc = {
    email,
    displayName,
    active: true,
    passwordManagedBy: 'firebase_auth',
    updatedAt: now,
  };

  if (role === 'branch_admin') {
    adminDoc.role = 'branch_admin';
    adminDoc.branchId = branchId;
  }

  if (dryRun) {
    console.log('[dry-run] Firestore admins/%s', email);
    console.log(JSON.stringify({ ...adminDoc, updatedAt: '<serverTimestamp>' }, null, 2));
    if (!firestoreOnly) {
      console.log('[dry-run] Auth create/update user:', email);
    }
    return;
  }

  const adminRef = db.collection('admins').doc(email);
  const existing = await adminRef.get();
  await adminRef.set(
    {
      ...adminDoc,
      ...(existing.exists ? {} : { createdAt: now }),
    },
    { merge: true },
  );
  console.log('Firestore: admins/%s (%s)', email, existing.exists ? 'merged' : 'created');

  if (firestoreOnly) {
    console.log('ข้าม Auth (--firestore-only)');
    return;
  }

  let authUser;
  try {
    authUser = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(authUser.uid, {
      password,
      displayName,
      disabled: false,
    });
    console.log('Auth: updated password for uid=%s', authUser.uid);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') {
      throw error;
    }
    authUser = await admin.auth().createUser({
      email,
      password,
      displayName,
      emailVerified: false,
    });
    console.log('Auth: created uid=%s', authUser.uid);
  }

  await adminRef.set(
    {
      authUid: authUser.uid,
      hasPasswordSet: true,
      updatedAt: now,
    },
    { merge: true },
  );
  console.log('Done. ส่งรหัสชั่วคราวให้ manager แล้วให้เปลี่ยนหลัง login');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
