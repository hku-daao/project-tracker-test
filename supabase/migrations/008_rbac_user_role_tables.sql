-- RBAC: UserTable, TeamTable (ref), RoleTable, SubordinateMapping, UserRoleMapping
-- Run after 001, 002 and seed (teams + staff exist). Adds 4th team if missing.

-- ========== 1. ROLES (RoleTable) ==========
CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id text NOT NULL UNIQUE,
  name text NOT NULL
);
COMMENT ON TABLE roles IS 'RoleTable: sys_admin, dept_head, supervisor, general';

INSERT INTO roles (app_id, name) VALUES
  ('sys_admin', 'System Admin'),
  ('dept_head', 'Department Head'),
  ('supervisor', 'Supervisor'),
  ('general', 'General')
ON CONFLICT (app_id) DO NOTHING;

-- ========== 2. APP USERS (UserTable) – links Firebase Auth to app ==========
CREATE TABLE IF NOT EXISTS app_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid text NOT NULL UNIQUE,
  email text NOT NULL,
  display_name text,
  staff_id uuid REFERENCES staff(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_app_users_firebase_uid ON app_users(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_app_users_staff ON app_users(staff_id);

-- ========== 3. USER ROLE MAPPING (UserRoleMapping) ==========
CREATE TABLE IF NOT EXISTS user_role_mapping (
  app_user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (app_user_id, role_id)
);
CREATE INDEX IF NOT EXISTS idx_user_role_mapping_role ON user_role_mapping(role_id);

-- ========== 4. SUBORDINATE MAPPING (Supervisor -> Subordinates) ==========
CREATE TABLE IF NOT EXISTS subordinate_mapping (
  supervisor_staff_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  subordinate_staff_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  PRIMARY KEY (supervisor_staff_id, subordinate_staff_id),
  CHECK (supervisor_staff_id != subordinate_staff_id)
);
CREATE INDEX IF NOT EXISTS idx_subordinate_mapping_sub ON subordinate_mapping(subordinate_staff_id);

-- ========== 5. FOURTH TEAM (if using 4 teams) ==========
-- Ensure we have 4 teams; add Alumni Affairs if not present
INSERT INTO teams (id, name, app_id) VALUES
  (gen_random_uuid(), 'Alumni Affairs Team', 'alumni_affairs')
ON CONFLICT (app_id) DO NOTHING;

-- ========== 6. TEAM MEMBERSHIP (staff in teams) ==========
-- 001 has team_members(team_id, staff_id, role). Ensure staff are linked to teams by app_id.
-- Flutter uses teams with directorIds/officerIds; Supabase has team_members.
-- Optional: add team_members rows from existing app logic or a separate seed.

-- ========== 7. RPC: assignable staff for a user (by Firebase UID) – server-side enforcement ==========
CREATE OR REPLACE FUNCTION get_assignable_staff(p_firebase_uid text)
RETURNS TABLE (
  staff_id uuid,
  staff_app_id text,
  staff_name text,
  team_id uuid,
  team_app_id text,
  team_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app_user_id uuid;
  v_staff_id uuid;
  v_role_app_id text;
BEGIN
  -- Get app user and role
  SELECT u.id, u.staff_id, r.app_id INTO v_app_user_id, v_staff_id, v_role_app_id
  FROM app_users u
  JOIN user_role_mapping urm ON urm.app_user_id = u.id
  JOIN roles r ON r.id = urm.role_id
  WHERE u.firebase_uid = p_firebase_uid
  LIMIT 1;

  IF v_app_user_id IS NULL THEN
    RETURN;
  END IF;

  -- sys_admin, dept_head: all staff from all teams
  IF v_role_app_id IN ('sys_admin', 'dept_head') THEN
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM staff s
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE s.app_id IS NOT NULL
    ORDER BY t.name NULLS LAST, s.name;
    RETURN;
  END IF;

  -- supervisor: only own subordinates
  IF v_role_app_id = 'supervisor' AND v_staff_id IS NOT NULL THEN
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM subordinate_mapping sub
    JOIN staff s ON s.id = sub.subordinate_staff_id
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE sub.supervisor_staff_id = v_staff_id AND s.app_id IS NOT NULL
    ORDER BY t.name NULLS LAST, s.name;
    RETURN;
  END IF;

  -- general: only self
  IF v_role_app_id = 'general' AND v_staff_id IS NOT NULL THEN
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM staff s
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE s.id = v_staff_id
    ORDER BY s.name;
  END IF;
END;
$$;

COMMENT ON FUNCTION get_assignable_staff(text) IS 'Returns staff the given user can assign to (by role). Call from backend after verifying Firebase token.';

-- ========== 8. RPC: current user profile (role + staff) for UI ==========
CREATE OR REPLACE FUNCTION get_user_profile(p_firebase_uid text)
RETURNS TABLE (
  role_app_id text,
  staff_id uuid,
  staff_app_id text,
  staff_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT r.app_id, u.staff_id, s.app_id, s.name
  FROM app_users u
  JOIN user_role_mapping urm ON urm.app_user_id = u.id
  JOIN roles r ON r.id = urm.role_id
  LEFT JOIN staff s ON s.id = u.staff_id
  WHERE u.firebase_uid = p_firebase_uid
  LIMIT 1;
END;
$$;
