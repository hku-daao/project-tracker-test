# Add 4 Firebase users to `app_users` with roles

| Email | Role |
|--------|------|
| lunanchow@hku.hk | supervisor |
| yang.wang@hku.hk | dept_head |
| kenkylee@hku.hk | supervisor |
| leec2@hku.hk | general |

## Steps

1. Ensure those 4 accounts exist in **Firebase Authentication** (same project as the app).
2. Ensure **`staff`** rows exist for those emails (from your Excel import / `016` migration).
3. From **`backend/`**, with `FIREBASE_SERVICE_ACCOUNT_JSON` set (same JSON as Railway — can use `backend/.env`):

   ```powershell
   cd backend
   node scripts/sync_app_users_from_firebase.js
   ```

4. Copy the **entire printed SQL** into **Supabase → SQL Editor** → Run.

The script resolves each user’s **Firebase UID** and generates `INSERT ... ON CONFLICT` for `app_users`, clears old `user_role_mapping` rows for those users, then inserts the correct role links.

## Troubleshooting

- **MISSING in Firebase Auth** — create the user in Firebase Console first (or sign up in the app).
- **`staff_id` is null** — add/fix the matching row in **`staff`** for that email.
