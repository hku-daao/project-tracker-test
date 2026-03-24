# RBAC (Role-Based Access Control) Setup

## 1. Run migrations

In Supabase SQL Editor, run in order:

- `008_rbac_user_role_tables.sql` – creates `app_users`, `roles`, `user_role_mapping`, `subordinate_mapping`, and RPCs `get_user_profile`, `get_assignable_staff`
- `009_team_members_seed.sql` – populates `team_members` so assignable staff have team info (run after seed_teams_and_staff)

## 2. Register a user and assign role

After a user signs in with Firebase (email/password), get their **Firebase UID** from Firebase Console → Authentication → Users, or from your app logs.

Then in Supabase SQL Editor:

```sql
-- Insert app user (replace with real firebase_uid and email)
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
VALUES (
  'THE_FIREBASE_UID_FROM_FIREBASE_CONSOLE',
  'user@example.com',
  'Display Name',
  NULL  -- or (SELECT id FROM staff WHERE app_id = 'may' LIMIT 1) to link to a staff
)
ON CONFLICT (firebase_uid) DO UPDATE SET email = EXCLUDED.email, display_name = EXCLUDED.display_name;

-- Assign sys_admin role (replace app_user id if needed)
INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT u.id, r.id FROM app_users u, roles r
WHERE u.firebase_uid = 'THE_FIREBASE_UID_FROM_FIREBASE_CONSOLE'
  AND r.app_id = 'sys_admin'
ON CONFLICT (app_user_id, role_id) DO NOTHING;
```

Use `dept_head`, `supervisor`, or `general` instead of `sys_admin` as needed.

## 3. Subordinate mapping (for supervisor role)

For a supervisor to see only their subordinates in the assignee dropdown:

```sql
-- Example: staff with app_id 'monica' is supervisor of 'funa', 'anthony_tai'
INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id FROM staff s1, staff s2
WHERE s1.app_id = 'monica' AND s2.app_id IN ('funa', 'anthony_tai')
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;
```

## 4. Backend environment variables

For `/api/me` and `/api/assignable-staff` (server-side assignee list):

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key (not anon) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Full JSON string of Firebase service account key (for verifying ID tokens) |

Get the service account: Firebase Console → Project Settings → Service accounts → Generate new private key. Paste the JSON as one line or escape it for your host (e.g. Railway).

## 5. Role behaviour (enforced by backend RPC)

- **sys_admin / dept_head**: See all teams and all staff; can select multiple teams and multiple assignees.
- **supervisor**: See only own subordinates (from `subordinate_mapping`); no team selection; multiple assignees.
- **general**: See only self; create initiative/task for self only.

View visibility in the app:

- **High-level View** (segment + tabs): only sys_admin and dept_head.
- **Low-level View** (3 tabs: Initiatives/ Tasks, Create Initiative/ Task, My Initiatives/ Tasks): sys_admin, dept_head, supervisor see all 3; general sees only Create and My Initiatives/ Tasks.
