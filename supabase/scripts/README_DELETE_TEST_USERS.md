# Delete test users (`test-super`, `test-dept`, `test-admin`)

This removes **only** those three accounts from **Firebase Auth** and **Supabase**.  
It does **not** remove `test-gen@test.com` or any `@hku.hk` users.

## 1. Supabase

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your project → **SQL Editor**.
2. Open `supabase/scripts/delete_test_users_three.sql` from this repo, paste into the editor, run.

If `DELETE FROM staff` fails because of unexpected foreign keys, run the `DELETE FROM app_users` / `user_role_mapping` parts only (comment out the staff `DELETE`), or fix the blocking rows first.

## 2. Firebase Authentication

**Option A – Console (simplest)**  
Firebase Console → **Authentication** → **Users** → search each email → **Delete user**:

- `test-super@test.com`
- `test-dept@test.com`
- `test-admin@test.com`

**Option B – Script** (uses the same service account as your backend)

From machine with Node and `backend/.env` containing `FIREBASE_SERVICE_ACCOUNT_JSON`:

```powershell
cd path\to\Project Tracker\backend
node scripts/delete_firebase_users_by_email.js
```

## 3. Order

You can run **Supabase first** or **Firebase first**; they are independent.  
For a clean state, do **both**.
