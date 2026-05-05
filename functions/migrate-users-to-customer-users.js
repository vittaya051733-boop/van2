/* eslint-disable no-console */
const admin = require('firebase-admin');

const SOURCE_COLLECTION = 'users';
const TARGET_COLLECTION = 'customer_users';
const MAX_BATCH_WRITES = 400;

// Usage:
//   node migrate-users-to-customer-users.js
//   node migrate-users-to-customer-users.js --dry-run
//   node migrate-users-to-customer-users.js --delete-source
//   node migrate-users-to-customer-users.js --uid=<firebase_uid> --delete-source

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

function parseArgs(argv) {
  const args = {
    dryRun: false,
    uid: null,
    deleteSource: false,
  };

  for (const token of argv.slice(2)) {
    if (token === '--dry-run') {
      args.dryRun = true;
      continue;
    }
    if (token.startsWith('--uid=')) {
      const uid = token.slice('--uid='.length).trim();
      args.uid = uid || null;
      continue;
    }
    if (token === '--delete-source') {
      args.deleteSource = true;
      continue;
    }
  }

  return args;
}

async function migrateOneUser({ uid, dryRun, deleteSource, writer }) {
  const sourceRef = db.collection(SOURCE_COLLECTION).doc(uid);
  const sourceSnap = await sourceRef.get();

  if (!sourceSnap.exists) {
    console.log(`- ข้าม ${uid}: ไม่พบเอกสารใน ${SOURCE_COLLECTION}`);
    return { migratedUsers: 0, migratedFriends: 0 };
  }

  const sourceData = sourceSnap.data() || {};
  const targetRef = db.collection(TARGET_COLLECTION).doc(uid);

  await writer.set(targetRef, {
    ...sourceData,
    migratedFrom: SOURCE_COLLECTION,
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  let migratedFriends = 0;
  const friendsSnap = await sourceRef.collection('friends').get();
  for (const friendDoc of friendsSnap.docs) {
    await writer.set(targetRef.collection('friends').doc(friendDoc.id), {
      ...(friendDoc.data() || {}),
      migratedFrom: `${SOURCE_COLLECTION}/friends`,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    migratedFriends += 1;
  }

  if (!dryRun && deleteSource) {
    await sourceRef.delete();
  }

  return { migratedUsers: 1, migratedFriends };
}

function createBatchWriter({ dryRun }) {
  let batch = db.batch();
  let pendingWrites = 0;
  let commits = 0;

  return {
    async set(ref, data) {
      if (dryRun) {
        return;
      }

      batch.set(ref, data, { merge: true });
      pendingWrites += 1;

      if (pendingWrites >= MAX_BATCH_WRITES) {
        await batch.commit();
        commits += 1;
        batch = db.batch();
        pendingWrites = 0;
      }
    },

    async flush() {
      if (dryRun || pendingWrites === 0) {
        return commits;
      }
      await batch.commit();
      commits += 1;
      pendingWrites = 0;
      return commits;
    },
  };
}

async function run() {
  const args = parseArgs(process.argv);
  const writer = createBatchWriter({ dryRun: args.dryRun });

  let userIds = [];
  if (args.uid) {
    userIds = [args.uid];
  } else {
    const usersSnap = await db.collection(SOURCE_COLLECTION).get();
    userIds = usersSnap.docs.map((doc) => doc.id);
  }

  if (userIds.length === 0) {
    console.log('ไม่พบข้อมูลผู้ใช้ใน users');
    return;
  }

  console.log(
    `[เริ่ม] ย้ายข้อมูล ${userIds.length} รายการ จาก ${SOURCE_COLLECTION} -> ${TARGET_COLLECTION}` +
      (args.dryRun ? ' (dry-run)' : '') +
      (args.deleteSource ? ' (delete-source)' : ''),
  );

  let migratedUsers = 0;
  let migratedFriends = 0;

  for (const uid of userIds) {
    const result = await migrateOneUser({
      uid,
      dryRun: args.dryRun,
      deleteSource: args.deleteSource,
      writer,
    });
    migratedUsers += result.migratedUsers;
    migratedFriends += result.migratedFriends;
  }

  const commits = await writer.flush();

  console.log(`[สำเร็จ] users: ${migratedUsers}, friends: ${migratedFriends}, commits: ${commits}`);
  if (args.dryRun) {
    console.log('dry-run: ยังไม่มีการเขียนข้อมูลจริง');
  }
  if (!args.dryRun && args.deleteSource) {
    console.log('ลบต้นทาง users แล้วตามรายการที่ migrate สำเร็จ');
  }
}

run().catch((error) => {
  console.error('[ผิดพลาด] migration ไม่สำเร็จ', error);
  process.exitCode = 1;
});
