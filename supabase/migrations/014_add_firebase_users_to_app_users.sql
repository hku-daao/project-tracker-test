-- ========================================
-- Add Firebase Authentication users to app_users table
-- ========================================
-- 
-- INSTRUCTIONS:
-- 1. Get Firebase UID and email from Firebase Console → Authentication → Users
-- 2. Replace the placeholder values below (2pLbiI9HgDPAc4VzgaKSXPn91WD3, email1@example.com, etc.)
-- 3. Optionally link to staff by staff.app_id (e.g., 'yang_wang', 'leec2')
-- 4. Assign a role: 'sys_admin', 'dept_head', 'supervisor', or 'general'
-- 5. Run this migration in Supabase SQL Editor
--
-- ========================================

-- ========================================
-- USER 1
-- ========================================
-- Replace these values:
--   '2pLbiI9HgDPAc4VzgaKSXPn91WD3' → Firebase UID from Firebase Console
--   'email1@example.com' → User's email
--   'Display Name 1' → Display name (or use email)
--   'lunan_chow' → Staff app_id (e.g., 'yang_wang') or NULL if not linking
--   'sys_admin' → Role: 'sys_admin', 'dept_head', 'supervisor', or 'general'

INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 
    '2pLbiI9HgDPAc4VzgaKSXPn91WD3',  -- ⬅️ REPLACE: Firebase UID
    'lunanchow@hku.hk',  -- ⬅️ REPLACE: Email address
    'Lunan Chow',  -- ⬅️ REPLACE: Display name (or use email)
    CASE 
        WHEN 'lunan_chow' IS NOT NULL AND 'lunan_chow' != '' THEN
            (SELECT id FROM staff WHERE app_id = 'lunan_chow' LIMIT 1)
        ELSE NULL
    END  -- ⬅️ REPLACE: Staff app_id or NULL
ON CONFLICT (firebase_uid) DO UPDATE SET
    email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    staff_id = EXCLUDED.staff_id;

-- Assign role to user 1
INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT 
    au.id,
    r.id
FROM app_users au
CROSS JOIN roles r
WHERE au.firebase_uid = '2pLbiI9HgDPAc4VzgaKSXPn91WD3'  -- ⬅️ REPLACE: Same Firebase UID as above
  AND r.app_id = 'supervisor'  -- ⬅️ REPLACE: 'sys_admin', 'dept_head', 'supervisor', or 'general'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- ========================================
-- USER 2
-- ========================================

INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 
    'UeeGfnchu8Txyc4ITfi0Pl9krQC3',  -- ⬅️ REPLACE: Firebase UID
    'kenkylee@hku.hk',  -- ⬅️ REPLACE: Email address
    'Ken Lee',  -- ⬅️ REPLACE: Display name
    CASE 
        WHEN 'ken_lee' IS NOT NULL AND 'ken_lee' != '' THEN
            (SELECT id FROM staff WHERE app_id = 'ken_lee' LIMIT 1)
        ELSE NULL
    END  -- ⬅️ REPLACE: Staff app_id or NULL
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
WHERE au.firebase_uid = 'UeeGfnchu8Txyc4ITfi0Pl9krQC3'  -- ⬅️ REPLACE: Same Firebase UID as above
  AND r.app_id = 'supervisor'  -- ⬅️ REPLACE: Desired role
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- ========================================
-- USER 3
-- ========================================

INSERT INTO app_users (firebase_uid, email, display_name, staff_id)
SELECT 
    '77K37F83MMbFHuKaEg61WELsz1j1',  -- ⬅️ REPLACE: Firebase UID
    'yang.wang@hku.hk',  -- ⬅️ REPLACE: Email address
    'Yang Wang',  -- ⬅️ REPLACE: Display name
    CASE 
        WHEN 'yang_wang' IS NOT NULL AND 'yang_wang' != '' THEN
            (SELECT id FROM staff WHERE app_id = 'yang_wang' LIMIT 1)
        ELSE NULL
    END  -- ⬅️ REPLACE: Staff app_id or NULL
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
WHERE au.firebase_uid = '77K37F83MMbFHuKaEg61WELsz1j1'  -- ⬅️ REPLACE: Same Firebase UID as above
  AND r.app_id = 'dept_head'  -- ⬅️ REPLACE: Desired role
ON CONFLICT (app_user_id, role_id) DO NOTHING;

-- ========================================
-- VERIFICATION QUERY
-- Run this after adding users to verify they were added correctly:
-- ========================================
-- SELECT 
--     au.id,
--     au.firebase_uid,
--     au.email,
--     au.display_name,
--     s.name as staff_name,
--     s.app_id as staff_app_id,
--     r.app_id as role
-- FROM app_users au
-- LEFT JOIN staff s ON s.id = au.staff_id
-- LEFT JOIN user_role_mapping urm ON urm.app_user_id = au.id
-- LEFT JOIN roles r ON r.id = urm.role_id
-- WHERE au.firebase_uid IN ('2pLbiI9HgDPAc4VzgaKSXPn91WD3', 'UeeGfnchu8Txyc4ITfi0Pl9krQC3', '77K37F83MMbFHuKaEg61WELsz1j1')
-- ORDER BY au.email;
