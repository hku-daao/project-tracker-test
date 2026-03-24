# Add `systemadmin@test.com` as System Admin (Supabase)

1. Account must exist in **Firebase Authentication** (`systemadmin@test.com`).

2. Ensure **`backend/.env`** contains **`FIREBASE_SERVICE_ACCOUNT_JSON`** (one-line service account JSON).

3. From **`backend/`**:

   ```powershell
   node scripts/add_firebase_user_to_supabase_sql.js systemadmin@test.com sys_admin "System Admin"
   ```

4. Copy the **printed SQL** into **Supabase → SQL Editor** → Run.

This sets **`app_users`** (Firebase UID + email + optional `staff_id` if a matching **`staff.email`** exists) and **`user_role_mapping`** → **`sys_admin`**.

**Optional:** If you want a **`staff`** row for this user, run the commented `INSERT INTO staff ...` from the generated SQL first (or uncomment it), then run the full script again so `staff_id` links.
