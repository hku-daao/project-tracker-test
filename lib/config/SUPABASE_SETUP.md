# Supabase setup (so initiatives sync to the DB)

> **Testing vs production:** The app switches Supabase projects using `DEPLOY_ENV` (see **`docs/ENVIRONMENTS.md`**). **DAAO Apps** is production; **DAAO Tests** is testing — use the anon key for the environment you are building.

## 1. Get your project URL and anon key

1. Open [Supabase Dashboard](https://supabase.com/dashboard) and select **DAAO Apps** (production) or **DAAO Tests** (testing), matching your build.
2. Go to **Project Settings** (gear icon) → **API**.
3. Copy:
   - **Project URL** (e.g. `https://xxxxxxxx.supabase.co`)
   - **anon public** key (long string under "Project API keys").

## 2. Put them in the app

Open **`lib/config/supabase_config.dart`**: set **`_testingAnonKey`** for default/testing builds, or use **`--dart-define=DEPLOY_ENV=production`** for production (uses **`_productionAnonKey`**). You can also pass **`--dart-define=SUPABASE_ANON_KEY=...`** to override.

Save the file and **hot restart** the app (or run `flutter run -d chrome` again).

## 3. Run seed in Supabase (if you haven’t)

In Supabase **SQL Editor**, run **`supabase/seed_teams_and_staff.sql`** (after migrations 001 and 002).  
Otherwise you’ll get an orange snackbar like “Team not found …”.

## 4. Create an initiative again

- **Green snackbar “Synced to Supabase”** → row is in **Table Editor → initiatives**.
- **Blue snackbar “Supabase not configured”** → anon key missing for this `DEPLOY_ENV` (set `_testingAnonKey` or `_productionAnonKey`, or `--dart-define=SUPABASE_ANON_KEY`).
- **Orange snackbar** → read the message (e.g. run seed, or fix RLS).

## 5. Tasks, milestones, comments (run migration 004)

In **SQL Editor**, run **`supabase/migrations/004_task_milestones.sql`**. This creates **`task_milestones`** (sub-tasks on tasks) and RLS policies so the app can read/write **tasks**, **task_assignees**, **task_milestones**, **comments** (insert), and **sub_tasks** (insert/update).

## 6. Website / production: load from Supabase

When Supabase is configured (`SupabaseConfig.isConfigured`), the app **starts by loading initiatives** (and sub-tasks + initiative comments) from Supabase, then shows the home screen.

- **Build for web** with the same `supabase_config.dart` values (or use `--dart-define` if you prefer not to commit keys).
- In Supabase, enable **SELECT** for the `anon` role on: `initiatives`, `teams`, `staff`, `initiative_directors`, `sub_tasks`, `comments` (or disable RLS on these tables for testing).

## 7. “Nothing in Supabase after refresh” — checklist

| Symptom | Cause |
|--------|--------|
| **Yellow banner** on home: “Supabase URL/key not set” | The **deployed** site was built without an anon key for that environment. Set `_testingAnonKey` / production key or `SUPABASE_ANON_KEY`, rebuild, deploy. |
| **Green** “Initiative synced to Supabase” but Table Editor is empty | You’re looking at a **different** Supabase project than the one for your build (`DEPLOY_ENV` + `supabase_config.dart`). |
| **Orange** snackbar after Create Initiative | Read the text: usually **run `seed_teams_and_staff.sql`**, or run migrations **003** (RLS + INSERT policies). |
| No orange snackbar, still empty DB | Open browser **DevTools → Network**, filter `supabase` / `rest`, create again — failed `POST` = RLS or wrong key. |
| Initiative missing but you added **sub-tasks** | Sub-tasks need the initiative row in DB first. If Create failed silently before, sub-tasks could not insert (FK). **Create initiative** must show green first. |
| **Sub-tasks gone after refresh** (initiative still there) | Almost always **missing SELECT on `sub_tasks` for anon**. Rows exist in Table Editor but the app can’t read them. Run **`007_sub_tasks_anon_select.sql`** in Supabase SQL Editor (or re-run the updated **`004`** block for `sub_tasks`). |

Example policy (read-only for everyone):

```sql
CREATE POLICY "Allow anon read initiatives" ON initiatives FOR SELECT TO anon USING (true);
-- Repeat for teams, staff, initiative_directors, sub_tasks, comments
```
