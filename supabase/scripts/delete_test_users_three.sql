-- =============================================================================
-- Remove ONLY these test accounts from Supabase (not test-gen@test.com):
--   test-super@test.com
--   test-dept@test.com
--   test-admin@test.com
--
-- Matches seed: staff.app_id = test_super | test_dept | test_admin
--
-- Run in Supabase Dashboard → SQL Editor (review, then Run).
-- Order: clear FKs → app_users → staff.
--
-- NOTE: Deleting staff rows CASCADE-deletes:
--   - team_members, subordinate_mapping rows for them
--   - initiative_directors, task_assignees junction rows for them
--   - comments where author_id is one of these staff (comments removed, not initiatives/tasks)
-- If DELETE staff fails, see error message; you may keep staff rows and only rely on
-- app_users deletion (users can no longer log in as those Firebase accounts).
-- =============================================================================

BEGIN;

-- 1) Subordinate links involving these test staff
DELETE FROM subordinate_mapping
WHERE supervisor_staff_id IN (SELECT id FROM staff WHERE app_id IN ('test_admin', 'test_dept', 'test_super'))
   OR subordinate_staff_id IN (SELECT id FROM staff WHERE app_id IN ('test_admin', 'test_dept', 'test_super'));

-- 2) Team membership for these staff
DELETE FROM team_members
WHERE staff_id IN (SELECT id FROM staff WHERE app_id IN ('test_admin', 'test_dept', 'test_super'));

-- 3) App login + RBAC (user_role_mapping rows removed via ON DELETE CASCADE from app_users)
DELETE FROM app_users
WHERE lower(trim(email)) IN (
  'test-super@test.com',
  'test-dept@test.com',
  'test-admin@test.com'
);

-- 4) Staff personas used only for these tests (see seed_test_users_four_roles.sql)
DELETE FROM staff
WHERE app_id IN ('test_admin', 'test_dept', 'test_super');

COMMIT;

-- Verify (should return 0 rows for these emails / app_ids)
-- SELECT * FROM app_users WHERE lower(email) LIKE 'test-%@test.com';
-- SELECT * FROM staff WHERE app_id IN ('test_admin','test_dept','test_super');
