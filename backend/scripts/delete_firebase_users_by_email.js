#!/usr/bin/env node
/**
 * Delete Firebase Auth users by email (does not touch Supabase).
 *
 * Usage (from backend folder, with service account in env):
 *   set FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
 *   node scripts/delete_firebase_users_by_email.js
 *
 * Or one-liner on Windows PowerShell (paste JSON carefully):
 *   $env:FIREBASE_SERVICE_ACCOUNT_JSON = Get-Content ..\.env -Raw  # if you store it there
 *   node scripts/delete_firebase_users_by_email.js
 *
 * Or: use Firebase Console → Authentication → Users → delete each user manually.
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const admin = require('firebase-admin');

const EMAILS = [
  'test-super@test.com',
  'test-dept@test.com',
  'test-admin@test.com',
];

const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
if (!json) {
  console.error('Missing FIREBASE_SERVICE_ACCOUNT_JSON');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(json)),
});

async function main() {
  for (const email of EMAILS) {
    try {
      const user = await admin.auth().getUserByEmail(email);
      await admin.auth().deleteUser(user.uid);
      console.log('Deleted Firebase user:', email, user.uid);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        console.log('Not found (skip):', email);
      } else {
        console.error('Error for', email, e.message);
      }
    }
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
