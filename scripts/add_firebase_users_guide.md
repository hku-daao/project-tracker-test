# Guide: Adding Firebase Users to Supabase app_users Table

This guide helps you add Firebase Authentication users to the Supabase `app_users` table.

## Step 1: Get Firebase User Information

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Authentication** → **Users**
4. For each user, copy:
   - **UID** (the unique identifier)
   - **Email** address
   - **Display name** (if set)

## Step 2: Link to Staff (Optional)

If you want to link the Firebase user to a staff member:

1. Check the `staff` table in Supabase to find the staff member's `app_id`
2. Examples: `yang_wang`, `leec2`, `jessicatai`, etc.
3. Use this `app_id` in the migration script

## Step 3: Choose a Role

Available roles:
- `sys_admin` - System Administrator (full access)
- `dept_head` - Department Head (can see High-level and Low-level views)
- `supervisor` - Supervisor (can assign to subordinates)
- `general` - General user (can only see own tasks)

## Step 4: Edit and Run Migration

1. Open `supabase/migrations/014_add_firebase_users_to_app_users.sql`
2. Replace the placeholder values:
   - `FIREBASE_UID_1`, `FIREBASE_UID_2`, `FIREBASE_UID_3` → Your actual Firebase UIDs
   - `user1@example.com`, etc. → Your actual email addresses
   - `User Display Name` → Display names (or leave as email)
   - `staff_app_id` → Staff `app_id` if linking to staff (or set to NULL)
   - Role values → Desired roles (`sys_admin`, `dept_head`, `supervisor`, or `general`)
3. Run the migration in Supabase SQL Editor

## Example

If you have a Firebase user:
- **UID**: `abc123xyz789`
- **Email**: `test-admin@test.com`
- **Staff**: Link to staff with `app_id` = `leec2`
- **Role**: `sys_admin`

The SQL would be:

```sql
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 
    'abc123xyz789',
    'test-admin@test.com',
    'test-admin@test.com',
    (SELECT id FROM staff WHERE app_id = 'leec2' LIMIT 1)
ON CONFLICT (firebase_uid) DO UPDATE SET
    email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    staff_id = EXCLUDED.staff_id;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT 
    au.id,
    r.id
FROM app_users au
CROSS JOIN roles r
WHERE au.firebase_uid = 'abc123xyz789'
  AND r.app_id = 'sys_admin'
ON CONFLICT (app_user_id, role_id) DO NOTHING;
```

## Verification

After running the migration, verify the users were added:

```sql
SELECT 
    au.id,
    au.firebase_uid,
    au.email,
    au.display_name,
    s.name as staff_name,
    s.app_id as staff_app_id,
    r.app_id as role
FROM app_users au
LEFT JOIN staff s ON s.id = au.staff_id
LEFT JOIN user_role_mapping urm ON urm.app_user_id = au.id
LEFT JOIN roles r ON r.id = urm.role_id
ORDER BY au.email;
```

## Troubleshooting

- **User not found after login**: Check that `firebase_uid` matches exactly (case-sensitive)
- **No role assigned**: Verify the role `app_id` exists in the `roles` table
- **Staff not linked**: Check that the `staff.app_id` value exists in the staff table
