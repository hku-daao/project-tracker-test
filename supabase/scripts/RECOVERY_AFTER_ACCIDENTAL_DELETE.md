# Recovery after accidental data loss (Supabase / Firebase)

## Important: there is no “undo” button in SQL

If `DELETE` / `TRUNCATE` ran successfully and committed, **PostgreSQL does not keep a rollback**.  
Recovery is only possible from:

1. **A backup** (Supabase automatic backups, or a dump you exported earlier), or  
2. **Re-running seed/import scripts** from this repo (rebuilds *reference* data, not your exact lost production rows).

---

## Option A — Restore from Supabase backup (best if available)

### Paid projects (Pro and up)

- Supabase Dashboard → **Project Settings** → **Database** → **Backups**  
- Use **Point-in-Time Recovery** or **download a backup** and restore, following [Supabase backup docs](https://supabase.com/docs/guides/platform/backups).

### Free tier

- **Daily backups are not retained the same way.** Check **Database** → **Backups** in the dashboard anyway.  
- If you ever ran `pg_dump` or exported CSVs, use those files.

**If you can restore a backup from *before* the delete:** do that first — it is the only way to get the **exact** old data back.

---

## Option B — Rebuild reference data from this repo (not a full rollback)

This only restores what is **defined in SQL files** in the repo (teams, staff seeds, team_members, RBAC seeds, etc.).  
**Initiatives, tasks, and comments** created only in the app are **gone** unless you have a backup.

### Typical order (adjust if your migrations already applied)

1. **Confirm schema** — migrations should already be applied. Do **not** re-run `001_initial_schema` if tables still exist (it would error).  
2. **Re-seed teams & staff** (safe to run if empty or using `ON CONFLICT`):

   - `supabase/seed_teams_and_staff.sql`

3. **RBAC tables** (if empty):

   - `supabase/migrations/008_rbac_user_role_tables.sql` — only if tables missing (uses `IF NOT EXISTS` for many objects).

4. **Team members** (links staff ↔ teams):

   - `supabase/migrations/009_team_members_seed.sql`

5. **Optional — large Excel import** (only if you use that dataset):

   - `supabase/migrations/012_import_excel_data_exact_match.sql` (large; review before running)

6. **`app_users` / Firebase-linked rows** — re-add using:

   - `supabase/migrations/014_add_firebase_users_to_app_users.sql` (edit UIDs/emails for real users), or  
   - Your own `INSERT` scripts.

7. **Test users** (optional):

   - `supabase/seed_test_users_four_roles.sql` (replace `PASTE_UID_*` with real Firebase UIDs from Console).

Run each file in **SQL Editor** after reading comments at the top of the file.

---

## Firebase Authentication

Deleted Auth users **cannot be restored** by Google. You must:

- **Create users again** (sign-up flow or Firebase Console → Add user), or  
- Restore only if you had exported something (rare).

`staff` / `app_users` rows in Supabase must match the **new** Firebase UIDs if you re-create accounts.

---

## What to do next

1. **Try Option A** (backup / PITR) in the Supabase dashboard immediately.  
2. If no backup: **Option B** to get a **working baseline** again.  
3. For initiatives/tasks/comments that lived only in the DB: recover only from **exports, Excel, or another copy** if you have them.

If you describe what is missing now (e.g. “tables exist but empty” vs “whole DB dropped”), we can narrow the exact SQL to run.
