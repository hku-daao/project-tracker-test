/**
 * Reads user_level_dump.json (from Excel "user level tables v1.xlsx") and writes
 * supabase/migrations/016_import_user_level_tables_v1.sql
 *
 * Run from supabase/:  node scripts/generate_import_user_level_sql.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const dumpPath = path.join(root, 'user_level_dump.json');
const outPath = path.join(root, 'migrations', '016_import_user_level_tables_v1.sql');

const data = JSON.parse(fs.readFileSync(dumpPath, 'utf8'));

const TEAM_MAP = {
  1: { app_id: 'fundraising', name: 'Fundraising Team' },
  2: { app_id: 'alumni', name: 'Alumni Affairs Team' },
  3: { app_id: 'advancement_intel', name: 'Advancement Intelligence Team' },
  4: { app_id: 'admin_team', name: 'Admin Team' },
};

const ROLE_MAP = {
  1: 'sys_admin',
  2: 'dept_head',
  3: 'supervisor',
  4: 'general',
};

function esc(s) {
  return String(s ?? '')
    .trim()
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "''");
}

function appIdFromEmail(email) {
  const local = String(email).split('@')[0] || '';
  return local.toLowerCase().replace(/\./g, '_').replace(/[^a-z0-9_]/g, '_');
}

function sqlStaff() {
  const lines = [];
  for (const row of data.staff) {
    const email = esc(row.loginID);
    const name = esc(row.username);
    const aid = appIdFromEmail(row.loginID);
    lines.push(
      `  ('${aid}', '${name}', '${email}')`,
    );
  }
  return `INSERT INTO staff (app_id, name, email)
VALUES
${lines.join(',\n')}
ON CONFLICT (app_id) DO UPDATE SET
  name = EXCLUDED.name,
  email = EXCLUDED.email;`;
}

function sqlTeams() {
  const lines = [];
  for (const row of data.teams) {
    const m = TEAM_MAP[row.teamid];
    if (!m) continue;
    lines.push(`  ('${esc(m.name)}', '${esc(m.app_id)}')`);
  }
  return `INSERT INTO teams (name, app_id)
VALUES
${lines.join(',\n')}
ON CONFLICT (app_id) DO UPDATE SET
  name = EXCLUDED.name;`;
}

function sqlSubordinate() {
  const lines = [];
  const uidToEmail = Object.fromEntries(
    data.staff.map((r) => [r.userid, r.loginID]),
  );
  for (const row of data.subordinate_mapping) {
    const se = uidToEmail[row.super_id];
    const sube = uidToEmail[row.subo_id];
    if (!se || !sube) continue;
    lines.push(
      `  ((SELECT id FROM staff WHERE lower(email) = lower('${esc(se)}') LIMIT 1), (SELECT id FROM staff WHERE lower(email) = lower('${esc(sube)}') LIMIT 1))`,
    );
  }
  return `-- Replace subordinate relationships from Excel (supervisor -> subordinate)
DELETE FROM subordinate_mapping;

INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)
VALUES
${lines.join(',\n')}
ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;`;
}

function sqlTeamMembers() {
  // teamid -> team app_id
  const teamApp = (tid) => TEAM_MAP[tid]?.app_id;
  // (excel_teamid, staff_userid) -> { isSuper, isSub }
  const cell = {};
  function add(tid, uid, role) {
    const k = `${tid}:${uid}`;
    if (!cell[k]) cell[k] = { isSuper: false, isSub: false };
    if (role === 'super') cell[k].isSuper = true;
    if (role === 'sub') cell[k].isSub = true;
  }
  for (const row of data.subordinate_mapping) {
    add(row.teamid, row.super_id, 'super');
    add(row.teamid, row.subo_id, 'sub');
  }
  const uidToEmail = Object.fromEntries(
    data.staff.map((r) => [r.userid, r.loginID]),
  );
  const values = [];
  for (const k of Object.keys(cell)) {
    const [tid, uid] = k.split(':').map(Number);
    const tapp = teamApp(tid);
    const email = uidToEmail[uid];
    if (!tapp || !email) continue;
    const { isSuper, isSub } = cell[k];
    const role =
      isSuper && !isSub ? 'director' : isSuper && isSub ? 'director' : 'officer';
    values.push(
      `  ((SELECT id FROM teams WHERE app_id = '${esc(tapp)}' LIMIT 1), (SELECT id FROM staff WHERE lower(email) = lower('${esc(email)}') LIMIT 1), '${role}')`,
    );
  }
  return `-- Team membership derived from subordinate_mapping (Excel has no separate team_members sheet).
-- Directors: appear only as supervisor in that team; officers: appear only as subordinate; both -> director.
DELETE FROM team_members;

INSERT INTO team_members (team_id, staff_id, role)
VALUES
${values.join(',\n')}
ON CONFLICT (team_id, staff_id) DO UPDATE SET
  role = EXCLUDED.role;`;
}

function sqlUserRoleMapping() {
  const lines = [];
  for (const row of data.user_role_mapping) {
    const uid = row.userid;
    const rid = row.roleid;
    const appId = ROLE_MAP[rid];
    if (!appId) continue;
    const staffRow = data.staff.find((s) => s.userid === uid);
    if (!staffRow) continue;
    const em = esc(staffRow.loginID);
    lines.push(`  -- userid ${uid} -> ${appId}
  SELECT au.id, r.id
  FROM app_users au
  CROSS JOIN roles r
  WHERE lower(au.email) = lower('${em}')
    AND r.app_id = '${appId}'`);
  }
  // Deduplicate with DISTINCT in subquery
  return `-- Link app_users to roles (only rows where app_users already exists with matching email).
INSERT INTO user_role_mapping (app_user_id, role_id)
${lines.join('\n  UNION ALL\n')}
ON CONFLICT (app_user_id, role_id) DO NOTHING;`;
}

const header = `-- =============================================================================
-- Import: user level tables v1.xlsx (staff, teams, roles reference, team_members,
--         subordinate_mapping, user_role_mapping where app_users exist)
-- Generated by: node scripts/generate_import_user_level_sql.js
-- Run in Supabase SQL Editor after backups. Review before executing.
-- =============================================================================

BEGIN;

`;

const footer = `
COMMIT;

-- Verify
-- SELECT COUNT(*) FROM staff;
-- SELECT COUNT(*) FROM teams WHERE app_id IN ('fundraising','alumni','advancement_intel','admin_team');
-- SELECT COUNT(*) FROM subordinate_mapping;
-- SELECT COUNT(*) FROM team_members;
`;

const body = [
  '-- 1) Roles (reference ids must match roles.app_id)',
  `INSERT INTO roles (app_id, name) VALUES
  ('sys_admin', 'System Admin'),
  ('dept_head', 'Department Head'),
  ('supervisor', 'Supervisor'),
  ('general', 'General')
ON CONFLICT (app_id) DO NOTHING;`,
  '',
  '-- 2) Teams',
  sqlTeams(),
  '',
  '-- 3) Staff',
  sqlStaff(),
  '',
  '-- 4) Subordinate mapping',
  sqlSubordinate(),
  '',
  '-- 5) Team members (derived)',
  sqlTeamMembers(),
  '',
  '-- 6) User ↔ role (requires Firebase-linked app_users with same email)',
  sqlUserRoleMapping(),
].join('\n');

fs.writeFileSync(outPath, header + body + footer, 'utf8');
console.log('Wrote', outPath);
