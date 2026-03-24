-- ========================================
-- Import Excel data with exact column matching
-- File: user level tables v1.xlsx
-- Generated automatically from Excel file
-- ========================================

-- ========== STEP 1: ALTER TABLES TO MATCH EXCEL COLUMNS ==========

-- Add Excel columns to staff table if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'userid') THEN
        ALTER TABLE staff ADD COLUMN userid text;
        CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_userid ON staff(userid) WHERE userid IS NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'loginID') THEN
        ALTER TABLE staff ADD COLUMN "loginID" text;
        CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_loginID ON staff("loginID") WHERE "loginID" IS NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'username') THEN
        ALTER TABLE staff ADD COLUMN username text;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'chinesename') THEN
        ALTER TABLE staff ADD COLUMN chinesename text;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'active') THEN
        ALTER TABLE staff ADD COLUMN active text DEFAULT '1';
    END IF;
END $$;

-- Add Excel columns to teams table if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'teams' AND column_name = 'teamid') THEN
        ALTER TABLE teams ADD COLUMN teamid text;
        CREATE UNIQUE INDEX IF NOT EXISTS idx_teams_teamid ON teams(teamid) WHERE teamid IS NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'teams' AND column_name = 'dept') THEN
        ALTER TABLE teams ADD COLUMN dept text;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'teams' AND column_name = 'team') THEN
        ALTER TABLE teams ADD COLUMN team text;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'teams' AND column_name = 'active') THEN
        ALTER TABLE teams ADD COLUMN active text DEFAULT '1';
    END IF;
END $$;

-- Add Excel columns to roles table if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'roles' AND column_name = 'roleid') THEN
        ALTER TABLE roles ADD COLUMN roleid text;
        CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_roleid ON roles(roleid) WHERE roleid IS NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'roles' AND column_name = 'role') THEN
        ALTER TABLE roles ADD COLUMN role text;
    END IF;
END $$;

-- ========== STEP 2: IMPORT DATA FROM EXCEL ==========

-- ========== STAFF ==========
-- Excel columns: userid, loginID, username, chinesename, hashedpwd, active

INSERT INTO staff (userid, loginID, username, chinesename, hashedpwd, active)
VALUES ('1', 'yang.wang@hku.hk', 'Yang Wang', NULL, NULL, '1')
ON CONFLICT (userid) DO UPDATE SET

-- ========== TEAMS ==========
-- Excel columns: teamid, dept, team, active

INSERT INTO teams (teamid, dept, team, active)
VALUES ('1', 'DAAO', 'Fundraising Team', '1')
ON CONFLICT (teamid) DO UPDATE SET

-- ========== ROLES ==========
-- Excel columns: roleid, role

INSERT INTO roles (roleid, role)
VALUES ('1', 'sys admin')
ON CONFLICT (roleid) DO UPDATE SET

-- ========== SUBORDINATE MAPPING ==========
-- Excel columns: smapid, teamid, super_id, subo_id, active

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '13'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '17'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '23'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '26'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '28'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '29'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '30'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '1' AND s2.userid = '36'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '13'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '17'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '23'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '26'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '28'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '29'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '30'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '2' AND s2.userid = '36'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '6'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '7'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '18'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '20'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '24'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '25'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '26'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '37'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '23' AND s2.userid = '38'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '26' AND s2.userid = '7'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '26' AND s2.userid = '24'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '26' AND s2.userid = '37'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '4'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '8'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '13'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '14'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '15'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '16'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '33'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '34'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '29' AND s2.userid = '35'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '5'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '9'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '11'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '12'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '17'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '19'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '21'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '22'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '27'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '30'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '31'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
SELECT s1.id, s2.id
FROM staff s1, staff s2
WHERE s1.userid = '28' AND s2.userid = '39'
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;


-- ========== USER ROLE MAPPING ==========
-- Excel columns: urmapid, userid, roleid

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '1'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '2'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '3'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '4'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '5'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '6'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '7'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '8'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '9'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '10'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '11'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '12'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '13'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '14'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '15'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '16'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '17'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '18'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '19'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '20'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '21'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '22'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '23'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '24'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '25'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '26'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '27'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '28'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '29'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '30'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '31'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '32'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '33'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '34'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '35'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '36'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '37'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '38'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '4'
WHERE s.userid = '39'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '2'
WHERE s.userid = '1'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '2'
WHERE s.userid = '2'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '1'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '2'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '6'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '9'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '13'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '15'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '17'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '23'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '25'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '26'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '27'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '28'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '29'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '30'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '32'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '3'
WHERE s.userid = '36'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '1'
WHERE s.userid = '7'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '1'
WHERE s.userid = '23'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '1'
WHERE s.userid = '24'
ON CONFLICT (app_user_id, role_id) DO NOTHING;

INSERT INTO user_role_mapping (app_user_id, role_id)
SELECT au.id, r.id
FROM app_users au
JOIN staff s ON s.id = au.staff_id
JOIN roles r ON r.roleid = '1'
WHERE s.userid = '26'
ON CONFLICT (app_user_id, role_id) DO NOTHING;


-- ========================================
-- End of import script
-- ========================================

