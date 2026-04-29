#!/usr/bin/env node

/**
 * One-time migration tool:
 * - Copies all rider documents from users/{uid} to riders/{uid}
 * - Merges all fields, preserving riders data when key already exists in riders
 * - Optionally deletes users/{uid} after successful copy when --delete-source is passed
 *
 * Usage:
 *   node scripts/migrate-users-to-riders.js
 *   node scripts/migrate-users-to-riders.js --delete-source
 *
 * Prerequisites:
 *   1) npm i firebase-admin
 *   2) Set GOOGLE_APPLICATION_CREDENTIALS to a service-account json path
 */

const admin = require('firebase-admin');

const shouldDeleteSource = process.argv.includes('--delete-source');

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });

  const db = admin.firestore();
  const usersRef = db.collection('users');
  const ridersRef = db.collection('riders');

  const riderUsersSnapshot = await usersRef
    .where('role', '==', 'rider')
    .get();

  console.log(`Found ${riderUsersSnapshot.size} rider docs in users.`);

  let migrated = 0;
  let skipped = 0;
  let deleted = 0;

  for (const doc of riderUsersSnapshot.docs) {
    const uid = doc.id;
    const sourceData = doc.data() || {};

    if (!uid || uid.trim() === '') {
      skipped += 1;
      continue;
    }

    const riderDocRef = ridersRef.doc(uid);
    const targetDoc = await riderDocRef.get();
    const targetData = targetDoc.exists ? targetDoc.data() || {} : {};

    // Keep existing riders fields authoritative when already present.
    const merged = {
      ...sourceData,
      ...targetData,
      uid,
      role: 'rider',
      userType: 'rider',
      migratedFromUsersAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await riderDocRef.set(merged, { merge: true });
    migrated += 1;

    if (shouldDeleteSource) {
      await doc.ref.delete();
      deleted += 1;
    }
  }

  console.log(`Migration completed. migrated=${migrated}, skipped=${skipped}, deleted=${deleted}`);
}

main().catch((error) => {
  console.error('Migration failed:', error);
  process.exitCode = 1;
});
