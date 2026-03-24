# Supabase – DAAO Apps (Project Tracker)

This folder contains the schema design and migration for storing **staff** and **task** data in your Supabase project **"DAAO Apps"**.

## Quick start

1. **Create or select the project**  
   In [Supabase Dashboard](https://supabase.com/dashboard), create a project named **DAAO Apps** (or use an existing one).

2. **Run the migrations**  
   - Open **SQL Editor** in the project.  
   - Run `migrations/001_initial_schema.sql`, then `migrations/002_add_app_id_for_sync.sql`.  
   - All tables will be created; `teams` and `staff` get an `app_id` column for Flutter sync.

3. **Seed teams and staff (for initiative sync)**  
   - Run `seed_teams_and_staff.sql` in the SQL Editor so the Flutter app can look up teams and directors by `app_id` when creating initiatives.

4. **Optional: Supabase CLI**  
   If you use the [Supabase CLI](https://supabase.com/docs/guides/cli):
   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

## Contents

| File | Purpose |
|------|--------|
| `schema-design.md` | Full table design, relationships, indexes, and data extraction notes |
| `migrations/001_initial_schema.sql` | SQL that creates all tables and indexes |
| `migrations/002_add_app_id_for_sync.sql` | Adds `app_id` to teams and staff for Flutter sync |
| `seed_teams_and_staff.sql` | Seed data so creating an initiative in Flutter inserts into Supabase |

## Tables created

- **Staff:** `staff`, `teams`, `team_members`
- **Initiatives:** `initiatives`, `initiative_directors`, `sub_tasks`
- **Tasks:** `tasks`, `task_assignees`
- **Comments:** `comments` (for both initiatives and tasks)
- **Audit:** `deleted_sub_tasks`, `deleted_tasks`

## Flutter initiative sync

When a user creates an initiative in the app, a row is inserted into Supabase `initiatives` and `initiative_directors` if:

1. **Supabase is configured** in the app: set `lib/config/supabase_config.dart` with your project URL and anon key (Dashboard → Project Settings → API).
2. **Migrations 001 and 002** are applied and **seed_teams_and_staff.sql** has been run so `teams` and `staff` have `app_id` values matching the Flutter app.

**If no row appears in Supabase:**

- After tapping "Create Initiative", check the **snackbar** (orange = error message, green = "Synced to Supabase").
- **"Team not found for app_id …"** or **"No directors found …"** → Run `seed_teams_and_staff.sql` in the SQL Editor.
- **Supabase not configured** → Set `url` and `anonKey` in `lib/config/supabase_config.dart`.
- **Permission/RLS errors** → In Supabase, Table Editor → select `initiatives` → ensure RLS allows insert with your anon key, or disable RLS for development (Dashboard → Authentication → Policies).

## Next steps

- Add [Row Level Security (RLS)](https://supabase.com/docs/guides/auth/row-level-security) and policies when you add authentication.  
- Optionally load initiatives from Supabase on app start instead of only in-memory state.
