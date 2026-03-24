-- Test users for RBAC: 4 staff rows + app_users + roles
-- Run in Supabase SQL Editor AFTER migrations 001, 002, 008 (roles table exists).
--
-- STEP 1: Run the INSERT INTO staff block below (no Firebase UIDs needed).
-- STEP 2: Firebase Console → Authentication → Users → copy each User UID for the 4 emails.
-- STEP 3: Replace PASTE_UID_ADMIN, PASTE_UID_DEPT, PASTE_UID_SUPER, PASTE_UID_GEN below with real UIDs.
-- STEP 4: Run the rest of this file.

-- ========== 1. Staff rows (unique app_id for Flutter / RPC) ==========
INSERT INTO staff (id, name, email, app_id) VALUES
  (gen_random_uuid(), 'Test Admin', 'test-admin@test.com', 'test_admin'),
  (gen_random_uuid(), 'Test Dept Head', 'test-dept@test.com', 'test_dept'),
  (gen_random_uuid(), 'Test Supervisor', 'test-super@test.com', 'test_super'),
  (gen_random_uuid(), 'Test General', 'test-gen@test.com', 'test_gen')
ON CONFLICT (app_id) DO UPDATE SET
  name = EXCLUDED.name,
  email = EXCLUDED.email;

-- ========== 2. App users + roles (REPLACE the four PASTE_UID_* placeholders) ==========

-- Sys admin
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 'PASTE_UID_ADMIN', 'test-admin@test.com', 'Test Admin', s.id
FROM staff s WHERE s.app_id = 'test_admin' LIMIT 1
ON CONFLICT (firebase_uid) DO UPDATE SET
  email = EXCLUDED.email,
  display_name = EXCLUDED.display_name,
  staff_id = EXCLUDED.staff_id;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT u.id, r.id FROM app_users u, roles r
WHERE u.email = 'test-admin@test.com' AND r.app_id = 'sys_admin'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- Dept head
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 'PASTE_UID_DEPT', 'test-dept@test.com', 'Test Dept Head', s.id
FROM staff s WHERE s.app_id = 'test_dept' LIMIT 1
ON CONFLICT (firebase_uid) DO UPDATE SET
  email = EXCLUDED.email,
  display_name = EXCLUDED.display_name,
  staff_id = EXCLUDED.staff_id;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT u.id, r.id FROM app_users u, roles r
WHERE u.email = 'test-dept@test.com' AND r.app_id = 'dept_head'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- Supervisor (subordinates: example Funa + Anthony; change app_ids if you prefer)
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 'PASTE_UID_SUPER', 'test-super@test.com', 'Test Supervisor', s.id
FROM staff s WHERE s.app_id = 'test_super' LIMIT 1
ON CONFLICT (firebase_uid) DO UPDATE SET
  email = EXCLUDED.email,
  display_name = EXCLUDED.display_name,
  staff_id = EXCLUDED.staff_id;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT u.id, r.id FROM app_users u, roles r
WHERE u.email = 'test-super@test.com' AND r.app_id = 'supervisor'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- Optional: map supervisor staff to real subordinates (by app_id)
INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT sup.id, sub.id
FROM staff sup, staff sub
WHERE sup.app_id = 'test_super'
  AND sub.app_id IN ('funa', 'anthony_tai')
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

-- General (self only)
INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 'PASTE_UID_GEN', 'test-gen@test.com', 'Test General', s.id
FROM staff s WHERE s.app_id = 'test_gen' LIMIT 1
ON CONFLICT (firebase_uid) DO UPDATE SET
  email = EXCLUDED.email,
  display_name = EXCLUDED.display_name,
  staff_id = EXCLUDED.staff_id;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT u.id, r.id FROM app_users u, roles r
WHERE u.email = 'test-gen@test.com' AND r.app_id = 'general'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- ========== 3. Verify ==========
SELECT u.email, u.firebase_uid, s.app_id AS staff_app_id, s.name AS staff_name, r.app_id AS role
FROM app_users u
LEFT JOIN staff s ON s.id = u.staff_id
LEFT JOIN user_role_mapping urm ON urm.app_user_id = u.id
LEFT JOIN roles r ON r.id = urm.role_id
WHERE u.email LIKE 'test-%@test.com'
ORDER BY u.email;
