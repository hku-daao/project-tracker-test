require('dotenv').config();
const http = require('http');
const { createClient } = require('@supabase/supabase-js');

const PORT = process.env.PORT || 3000;

// Trim — copy/paste in Railway sometimes adds trailing newlines, which breaks Supabase URL.
const SUPABASE_URL = (process.env.SUPABASE_URL || '').trim();
const SUPABASE_SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const FIREBASE_SERVICE_ACCOUNT_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || 'test-admin@test.com').toLowerCase();

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
  'Access-Control-Max-Age': '86400',
};

function applyCors(res, statusCode, extraHeaders = {}) {
  res.writeHead(statusCode, { ...corsHeaders, ...extraHeaders });
}

function sendJson(res, statusCode, data) {
  applyCors(res, statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

let firebaseAdmin = null;
if (FIREBASE_SERVICE_ACCOUNT_JSON) {
  try {
    firebaseAdmin = require('firebase-admin');
    const serviceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
    firebaseAdmin.initializeApp({ credential: firebaseAdmin.credential.cert(serviceAccount) });
  } catch (e) {
    console.warn('Firebase Admin init failed:', e.message);
  }
}

const supabase = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  : null;

async function verifyFirebaseToken(authHeader) {
  if (!firebaseAdmin || !authHeader || !authHeader.startsWith('Bearer ')) return null;
  const idToken = authHeader.slice(7);
  try {
    const decoded = await firebaseAdmin.auth().verifyIdToken(idToken);
    return { uid: decoded.uid, email: (decoded.email || '').toLowerCase() };
  } catch (_) {
    return null;
  }
}

async function fetchProfileByEmail(email) {
  if (!supabase || !email) return null;
  const { data: rows, error } = await supabase
    .from('app_users')
    .select(`
      id,
      firebase_uid,
      email,
      staff_id,
      staff ( app_id, name ),
      user_role_mapping ( roles ( app_id ) )
    `)
    .eq('email', email.toLowerCase())
    .limit(1);
  if (error || !rows || !rows[0]) return null;
  const u = rows[0];
  const urm = u.user_role_mapping;
  let roleAppId = null;
  if (Array.isArray(urm) && urm.length) {
    roleAppId = urm[0].roles?.app_id || null;
  } else if (urm && urm.roles) {
    roleAppId = urm.roles.app_id;
  }
  const staff = u.staff;
  const staffObj = Array.isArray(staff) ? staff[0] : staff;
  return {
    role_app_id: roleAppId,
    staff_id: u.staff_id,
    staff_app_id: staffObj?.app_id || null,
    staff_name: staffObj?.name || null,
    firebase_uid_for_rpc: u.firebase_uid,
  };
}

async function handleApiMe(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(res, 401, { error: 'Unauthorized', message: 'Invalid or missing Firebase token' });
    return;
  }
  if (!supabase) {
    sendJson(res, 503, { error: 'Supabase not configured' });
    return;
  }
  try {
    const { uid, email } = session;
    const profileRes = await supabase.rpc('get_user_profile', { p_firebase_uid: uid });
    let profileRow = profileRes.data && profileRes.data[0];
    let uidForAssignable = uid;

    if (!profileRow && email) {
      const byEmail = await fetchProfileByEmail(email);
      if (byEmail) {
        profileRow = {
          role_app_id: byEmail.role_app_id,
          staff_id: byEmail.staff_id,
          staff_app_id: byEmail.staff_app_id,
          staff_name: byEmail.staff_name,
        };
        uidForAssignable = byEmail.firebase_uid_for_rpc || uid;
      }
    }

    const assignableRes = await supabase.rpc('get_assignable_staff', {
      p_firebase_uid: uidForAssignable,
    });
    let assignableStaff = assignableRes.data || [];
    if ((!assignableStaff || assignableStaff.length === 0) && uidForAssignable !== uid) {
      const retry = await supabase.rpc('get_assignable_staff', { p_firebase_uid: uid });
      assignableStaff = retry.data || [];
    }

    if (!profileRow) {
      sendJson(res, 200, { role: null, staffId: null, staffAppId: null, assignableStaff: [] });
      return;
    }
    sendJson(res, 200, {
      role: profileRow.role_app_id,
      staffId: profileRow.staff_id,
      staffAppId: profileRow.staff_app_id || null,
      staffName: profileRow.staff_name || null,
      assignableStaff: assignableStaff.map((r) => ({
        staffId: r.staff_id,
        staffAppId: r.staff_app_id,
        staffName: r.staff_name,
        teamId: r.team_id,
        teamAppId: r.team_app_id,
        teamName: r.team_name,
      })),
    });
  } catch (e) {
    console.error('get_user_profile / get_assignable_staff:', e);
    sendJson(res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiAssignableStaff(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(res, 503, { error: 'Supabase not configured' });
    return;
  }
  try {
    const byEmail = await fetchProfileByEmail(session.email);
    const uidForAssignable = byEmail?.firebase_uid_for_rpc || session.uid;
    const { data, error } = await supabase.rpc('get_assignable_staff', {
      p_firebase_uid: uidForAssignable,
    });
    if (error) throw error;
    sendJson(res, 200, { assignableStaff: data || [] });
  } catch (e) {
    console.error('get_assignable_staff:', e);
    sendJson(res, 500, { error: 'Server error', message: e.message });
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => { data += chunk; });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

async function requireAdmin(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return null;
  }
  if ((session.email || '').toLowerCase() !== ADMIN_EMAIL) {
    sendJson(res, 403, { error: 'Forbidden', message: 'Admin only' });
    return null;
  }
  if (!supabase) {
    sendJson(res, 503, { error: 'Supabase not configured' });
    return null;
  }
  return session;
}

async function handleAdminSnapshot(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const [teams, roles, staff, appUsers, urm, tm, sub] = await Promise.all([
      supabase.from('teams').select('*').order('name'),
      supabase.from('roles').select('*').order('app_id'),
      supabase.from('staff').select('*').order('name'),
      supabase.from('app_users').select('*').order('email'),
      supabase.from('user_role_mapping').select('app_user_id, role_id'),
      supabase.from('team_members').select('team_id, staff_id, role'),
      supabase.from('subordinate_mapping').select('supervisor_staff_id, subordinate_staff_id'),
    ]);
    sendJson(res, 200, {
      teams: teams.data || [],
      roles: roles.data || [],
      staff: staff.data || [],
      appUsers: appUsers.data || [],
      userRoleMapping: urm.data || [],
      teamMembers: tm.data || [],
      subordinateMapping: sub.data || [],
    });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleAdminUpsertUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { firebase_uid, email, display_name, staff_app_id, role_app_id } = body;
    if (!firebase_uid || !email || !role_app_id) {
      sendJson(res, 400, { error: 'firebase_uid, email, role_app_id required' });
      return;
    }
    let staffId = null;
    if (staff_app_id) {
      const { data: s } = await supabase.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
      staffId = s?.id || null;
    }
    const { data: roleRow } = await supabase.from('roles').select('id').eq('app_id', role_app_id).maybeSingle();
    if (!roleRow) {
      sendJson(res, 400, { error: 'Invalid role_app_id' });
      return;
    }
    const { data: userRow, error: uErr } = await supabase
      .from('app_users')
      .upsert(
        { firebase_uid, email, display_name: display_name || email, staff_id: staffId },
        { onConflict: 'firebase_uid' },
      )
      .select('id')
      .single();
    if (uErr) throw uErr;
    await supabase.from('user_role_mapping').delete().eq('app_user_id', userRow.id);
    await supabase.from('user_role_mapping').insert({ app_user_id: userRow.id, role_id: roleRow.id });
    sendJson(res, 200, { ok: true, appUserId: userRow.id });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleAdminDeleteUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const id = url.pathname.split('/').pop();
  if (!id) {
    sendJson(res, 400, { error: 'Missing id' });
    return;
  }
  try {
    await supabase.from('user_role_mapping').delete().eq('app_user_id', id);
    await supabase.from('app_users').delete().eq('id', id);
    sendJson(res, 200, { ok: true });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleAdminUpsertTeam(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { name, app_id } = body;
    if (!name || !app_id) {
      sendJson(res, 400, { error: 'name, app_id required' });
      return;
    }
    const { error } = await supabase.from('teams').upsert(
      { name, app_id },
      { onConflict: 'app_id' },
    );
    if (error) throw error;
    sendJson(res, 200, { ok: true });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleAdminTeamMember(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { team_app_id, staff_app_id, role } = body;
    if (!team_app_id || !staff_app_id || !role) {
      sendJson(res, 400, { error: 'team_app_id, staff_app_id, role required' });
      return;
    }
    const { data: t } = await supabase.from('teams').select('id').eq('app_id', team_app_id).maybeSingle();
    const { data: s } = await supabase.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
    if (!t || !s) {
      sendJson(res, 400, { error: 'Team or staff not found' });
      return;
    }
    const { error } = await supabase.from('team_members').upsert(
      { team_id: t.id, staff_id: s.id, role },
      { onConflict: 'team_id,staff_id' },
    );
    if (error) throw error;
    sendJson(res, 200, { ok: true });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleAdminSubordinate(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { supervisor_staff_app_id, subordinate_staff_app_id } = body;
    if (!supervisor_staff_app_id || !subordinate_staff_app_id) {
      sendJson(res, 400, { error: 'supervisor_staff_app_id, subordinate_staff_app_id required' });
      return;
    }
    const { data: sup } = await supabase.from('staff').select('id').eq('app_id', supervisor_staff_app_id).maybeSingle();
    const { data: sub } = await supabase.from('staff').select('id').eq('app_id', subordinate_staff_app_id).maybeSingle();
    if (!sup || !sub) {
      sendJson(res, 400, { error: 'Staff not found' });
      return;
    }
    const { error } = await supabase.from('subordinate_mapping').upsert(
      { supervisor_staff_id: sup.id, subordinate_staff_id: sub.id },
      { onConflict: 'supervisor_staff_id,subordinate_staff_id' },
    );
    if (error) throw error;
    sendJson(res, 200, { ok: true });
  } catch (e) {
    sendJson(res, 500, { error: e.message });
  }
}

async function handleApiTeams(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(res, 503, { error: 'Supabase not configured' });
    return;
  }
  try {
    const { data: teamsData, error: teamsError } = await supabase
      .from('teams')
      .select('id, app_id, name')
      .order('name');
    if (teamsError) {
      console.error('handleApiTeams: teams query error:', teamsError);
      throw teamsError;
    }
    console.log(`handleApiTeams: Found ${(teamsData || []).length} teams`);

    const { data: teamMembersData, error: tmError } = await supabase
      .from('team_members')
      .select('team_id, staff_id, role, staff ( app_id, name )')
      .order('role');
    if (tmError) {
      console.error('handleApiTeams: team_members query error:', tmError);
      throw tmError;
    }
    console.log(`handleApiTeams: Found ${(teamMembersData || []).length} team members`);

    const isDirectorRole = (r) =>
      r === 'director' || r === 'lead';
    const isOfficerRole = (r) =>
      r === 'officer' || r === 'member';

    const teams = (teamsData || []).map((team) => {
      const members = (teamMembersData || []).filter((tm) => tm.team_id === team.id);
      const directors = members
        .filter((tm) => isDirectorRole(tm.role))
        .map((tm) => {
          const staff = Array.isArray(tm.staff) ? tm.staff[0] : tm.staff;
          return staff?.app_id || null;
        })
        .filter((id) => id != null);
      const officers = members
        .filter((tm) => isOfficerRole(tm.role))
        .map((tm) => {
          const staff = Array.isArray(tm.staff) ? tm.staff[0] : tm.staff;
          return staff?.app_id || null;
        })
        .filter((id) => id != null);
      return {
        id: team.app_id,
        name: team.name,
        directorIds: directors,
        officerIds: officers,
      };
    });

    console.log(`handleApiTeams: Returning ${teams.length} teams with members`);
    sendJson(res, 200, { teams });
  } catch (e) {
    console.error('handleApiTeams:', e);
    sendJson(res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiStaff(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(res, 503, { error: 'Supabase not configured' });
    return;
  }
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('app_id, name')
      .order('name');
    if (error) {
      console.error('handleApiStaff: query error:', error);
      throw error;
    }
    const staff = (data || []).map((s) => ({
      id: s.app_id,
      name: s.name,
    }));
    console.log(`handleApiStaff: Returning ${staff.length} staff members`);
    sendJson(res, 200, { staff });
  } catch (e) {
    console.error('handleApiStaff:', e);
    sendJson(res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleHealth(req, res) {
  sendJson(res, 200, {
    ok: true,
    message: 'Project Tracker backend',
    timestamp: new Date().toISOString(),
    // Safe diagnostics (no secrets). If supabaseConfigured is false, check Railway Variables on THIS service.
    firebaseConfigured: !!firebaseAdmin,
    supabaseConfigured: !!supabase,
    env: {
      supabaseUrlSet: SUPABASE_URL.length > 0,
      supabaseServiceRoleKeySet: SUPABASE_SERVICE_ROLE_KEY.length > 0,
    },
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    applyCors(res, 204);
    res.end();
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/api/me' && req.method === 'GET') {
    await handleApiMe(req, res);
    return;
  }
  if (path === '/api/assignable-staff' && req.method === 'GET') {
    await handleApiAssignableStaff(req, res);
    return;
  }
  if (path === '/api/teams' && req.method === 'GET') {
    await handleApiTeams(req, res);
    return;
  }
  if (path === '/api/staff' && req.method === 'GET') {
    await handleApiStaff(req, res);
    return;
  }
  if (path === '/api/admin/snapshot' && req.method === 'GET') {
    await handleAdminSnapshot(req, res);
    return;
  }
  if (path === '/api/admin/user' && req.method === 'POST') {
    await handleAdminUpsertUser(req, res);
    return;
  }
  if (path.startsWith('/api/admin/user/') && req.method === 'DELETE') {
    await handleAdminDeleteUser(req, res);
    return;
  }
  if (path === '/api/admin/team' && req.method === 'POST') {
    await handleAdminUpsertTeam(req, res);
    return;
  }
  if (path === '/api/admin/team-member' && req.method === 'POST') {
    await handleAdminTeamMember(req, res);
    return;
  }
  if (path === '/api/admin/subordinate' && req.method === 'POST') {
    await handleAdminSubordinate(req, res);
    return;
  }
  if (path === '/health' || path === '/') {
    await handleHealth(req, res);
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
  console.log(
    `Firebase Admin: ${firebaseAdmin ? 'ok' : 'missing FIREBASE_SERVICE_ACCOUNT_JSON'}`,
  );
  console.log(
    `Supabase: ${supabase ? 'ok' : 'missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY'}`,
  );
});
