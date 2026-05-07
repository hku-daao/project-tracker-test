require('dotenv').config();
const crypto = require('crypto');
const http = require('http');
const cron = require('node-cron');
const { createClient } = require('@supabase/supabase-js');

const MAILGUN_API_KEY = (process.env.MAILGUN_API_KEY || '').trim();
const MAILGUN_DOMAIN = (process.env.MAILGUN_DOMAIN || '').trim();
const MAILGUN_BASE_URL = (process.env.MAILGUN_BASE_URL || 'https://api.mailgun.net').trim().replace(/\/$/, '');
const MAILGUN_FROM = (process.env.MAILGUN_FROM || '').trim();
/** Verified From for task-assignment emails. Override with MAILGUN_NOTIFICATION_FROM for production domains. */
const MAILGUN_NOTIFICATION_FROM =
  (process.env.MAILGUN_NOTIFICATION_FROM || '').trim() ||
  'no-reply@sandbox1d79a2f6002c44b28ab0f0ec99a11179.mailgun.org';
/** Public web app origin for task links in emails (no trailing slash). */
const PUBLIC_WEB_APP_URL = (process.env.PUBLIC_WEB_APP_URL || 'https://projecttracker.hku.hk').trim().replace(/\/$/, '');
/** Marketing / landing URL for “Project Tracker” link in comment emails (no trailing slash). */
const PROJECT_TRACKER_LANDING_URL = (
  process.env.PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk'
).trim().replace(/\/$/, '');
/** Same base as [PROJECT_TRACKER_LANDING_URL] with trailing slash (overdue email templates). */
const OVERDUE_REMINDER_LANDING_HREF = `${PROJECT_TRACKER_LANDING_URL}/`;

/**
 * Flutter web deep link: hash query survives many email clients better than `?subtask=` alone.
 * Must match `lib/web_deep_link_web.dart` parsing of `location.hash` / fragment.
 */
function subtaskWebAppUrl(subtaskId) {
  const id = String(subtaskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || 'https://projecttracker.hku.hk').trim().replace(/\/$/, '');
  return `${base}/#/?subtask=${encodeURIComponent(id)}`;
}

/** Flutter web deep link for task detail (hash survives many email clients). */
function taskWebAppUrl(taskId) {
  const id = String(taskId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || 'https://projecttracker.hku.hk').trim().replace(/\/$/, '');
  return `${base}/#/?task=${encodeURIComponent(id)}`;
}

/** Flutter web deep link for project detail (`/#/?project=` matches [web_deep_link_web.dart]). */
function projectWebAppUrl(projectId) {
  const id = String(projectId || '').trim();
  const base = String(PUBLIC_WEB_APP_URL || 'https://projecttracker.hku.hk').trim().replace(/\/$/, '');
  return `${base}/#/?project=${encodeURIComponent(id)}`;
}

/** “Project Tracker” footer link in task-updated assignee emails (fixed product URL). */
const TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF = 'https://projecttracker.hku.hk/';

/** Allowed keys from Flutter for task-updated email lines (display label is server-side). */
const TASK_UPDATE_NOTIFY_FIELD_LABELS = {
  taskName: 'Task name',
  description: 'Description',
  assignees: 'Assignees',
  priority: 'Priority',
  startDate: 'Start date',
  dueDate: 'Due date',
};

const TASK_UPDATE_NOTIFY_MAX_CHANGES = 8;
const TASK_UPDATE_NOTIFY_MAX_VALUE_LEN = 4000;
const TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN = 8000;

/** Allowed keys from Flutter for sub-task-updated email lines (display label is server-side). */
const SUBTASK_UPDATE_NOTIFY_FIELD_LABELS = {
  subtaskName: 'Sub-task name',
  description: 'Description',
  assignees: 'Assignees',
  priority: 'Priority',
  startDate: 'Start date',
  dueDate: 'Due date',
};

/** Allowed keys from Flutter for project-updated email lines (display label is server-side). */
const PROJECT_UPDATE_NOTIFY_FIELD_LABELS = {
  projectName: 'Project name',
  description: 'Description',
  assignees: 'Assignee(s)',
  pic: 'PIC(s)',
  status: 'Status',
  startDate: 'Start date',
  endDate: 'End date',
};

/**
 * Task-updated assignee email: Aptos 16px; first block = field lines and/or comment line
 * per product template (double break between field block and comment when both present).
 *
 * @param {{ recipientDisplayName: string, changeLinesHtml: string, changeLinesText: string, commentLineHtml: string, commentLineText: string, taskName: string, taskUrl: string, updaterName: string, updatedAtLine: string }} p
 */
function buildTaskUpdatedAssigneeEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  const safeTaskUrlAttr = escapeHtml(p.taskUrl);
  const safeTitle = escapeHtml(p.taskName);
  const safeUpdater = escapeHtml(p.updaterName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF);
  const chHtml = (p.changeLinesHtml || '').trim();
  const cmtHtml = (p.commentLineHtml || '').trim();
  const topParts = [];
  if (chHtml) topParts.push(chHtml);
  if (cmtHtml) topParts.push(cmtHtml);
  const topBlock = topParts.join('<br><br>');
  const defaultLine =
    '<span style="color:#000000;font-family:Aptos,\'Segoe UI\',Calibri,sans-serif;font-size:16px;">The task has been updated.</span>';
  const firstBlock = topBlock ? topBlock : defaultLine;
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
${firstBlock}<br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildTaskUpdatedAssigneeEmailText(p) {
  const ch = (p.changeLinesText || '').trim();
  const cmt = (p.commentLineText || '').trim();
  const topParts = [];
  if (ch) topParts.push(ch);
  if (cmt) topParts.push(cmt);
  const top = topParts.join('\n\n');
  const first = top ? top : 'The task has been updated.';
  return `Hi ${p.recipientDisplayName},

${first}

${p.taskName}
${p.taskUrl}

Updated by: ${p.updaterName}

Updated at: ${p.updatedAtLine}

Project Tracker
${TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/**
 * Sub-task-updated notify email (creator save only): Aptos 16px; `changeLines*` = `{A} is updated – {value}`;
 * optional `commentLine*` = `Sub-task comment is added – …`; title link; Updated by / at; Project Tracker.
 *
 * @param {{ recipientDisplayName: string, changeLinesHtml: string, changeLinesText: string, commentLineHtml: string, commentLineText: string, subtaskName: string, subtaskUrl: string, updaterName: string, updatedAtLine: string }} p
 */
function buildSubtaskUpdatedAssigneeEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  const safeUrlAttr = escapeHtml(p.subtaskUrl);
  const safeTitle = escapeHtml(p.subtaskName);
  const safeUpdater = escapeHtml(p.updaterName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF);
  const chHtml = (p.changeLinesHtml || '').trim();
  const cmtHtml = (p.commentLineHtml || '').trim();
  const topParts = [];
  if (chHtml) topParts.push(chHtml);
  if (cmtHtml) topParts.push(cmtHtml);
  const topBlock = topParts.join('<br><br>');
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
${topBlock}<br><br>
<a href="${safeUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildSubtaskUpdatedAssigneeEmailText(p) {
  const ch = (p.changeLinesText || '').trim();
  const cmt = (p.commentLineText || '').trim();
  const topParts = [];
  if (ch) topParts.push(ch);
  if (cmt) topParts.push(cmt);
  const topBlock = topParts.join('\n\n');
  return `Hi ${p.recipientDisplayName},

${topBlock}

${p.subtaskName}
${p.subtaskUrl}

Updated by: ${p.updaterName}

Updated at: ${p.updatedAtLine}

Project Tracker
${SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/** Task-comment emails (`handleNotifyTaskComment`). Default on; set `TASK_COMMENT_EMAIL_ENABLED=false` to disable. */
const TASK_COMMENT_EMAIL_ENABLED = (() => {
  const v = (process.env.TASK_COMMENT_EMAIL_ENABLED || 'true').trim().toLowerCase();
  return !['false', '0', 'no', 'off'].includes(v);
})();

/** POST /api/cron/* — optional shared secret (Railway / external scheduler). */
const CRON_SECRET = (process.env.CRON_SECRET || '').trim();

const PORT = process.env.PORT || 3000;

// Trim — copy/paste in Railway sometimes adds trailing newlines, which breaks Supabase URL.
const SUPABASE_URL = (process.env.SUPABASE_URL || '').trim();
const SUPABASE_SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const FIREBASE_SERVICE_ACCOUNT_JSON = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '';
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || 'test-admin@test.com').toLowerCase();

/// Origins allowed to call this API from the browser (Flutter web).
/// Override or extend with Railway env: CORS_ORIGINS=https://a.com,https://b.com
const DEFAULT_CORS_ORIGINS = [
  'https://project-tracker-test.web.app',
  'https://project-tracker-test.firebaseapp.com',
  'https://project-tracker-production.web.app',
  'https://project-tracker-production.firebaseapp.com',
  'https://daao-a20c6.web.app',
  'https://testprojectmanagementtracking.firebaseapp.com',
  'https://projecttrackertest.hku-ia.ai',
  'https://projecttracker.hku.hk',
  'https://projecttracker.hku-ia.ai',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
];

function allowedOriginsSet() {
  const fromEnv = (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  return new Set([...DEFAULT_CORS_ORIGINS, ...fromEnv]);
}

/** Per-request CORS: echo preflight headers + allowlist Origin (required for browser + Authorization). */
function buildCorsHeaders(req) {
  const origin = req.headers.origin;
  const allow = allowedOriginsSet();
  const h = {
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Max-Age': '86400',
  };
  if (origin && allow.has(origin)) {
    h['Access-Control-Allow-Origin'] = origin;
    h.Vary = 'Origin';
  } else {
    h['Access-Control-Allow-Origin'] = '*';
  }
  const reqHdr = req.headers['access-control-request-headers'];
  h['Access-Control-Allow-Headers'] =
    reqHdr || 'Authorization, Content-Type, Accept, X-Requested-With';
  return h;
}

function applyCors(req, res, statusCode, extraHeaders = {}) {
  res.writeHead(statusCode, { ...buildCorsHeaders(req), ...extraHeaders });
}

function sendJson(req, res, statusCode, data) {
  applyCors(req, res, statusCode, { 'Content-Type': 'application/json' });
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
    const sk = decoded.staffKey;
    const staffKey =
      typeof sk === 'string' && sk.trim() ? sk.trim() : null;
    return {
      uid: decoded.uid,
      email: (decoded.email || '').toLowerCase(),
      staffKey,
    };
  } catch (_) {
    return null;
  }
}

/** Short-lived attachment stream tickets (PDF viewers issue multiple GET/Range requests). */
const ATTACHMENT_STREAM_TTL_MS = 300000;

function getAttachmentStreamSigningSecret() {
  const s = (
    process.env.ATTACHMENT_STREAM_SIGNING_SECRET ||
    process.env.CRON_SECRET ||
    ''
  ).trim();
  return s;
}

/**
 * Signed ticket: base64url(JSON).base64url(HMAC-SHA256(secret, payloadB64)).
 * Stateless across Railway instances; reusable until [exp] for Range/subrequests.
 */
function createAttachmentStreamTicket(objectPath, contentType, expMs) {
  const secret = getAttachmentStreamSigningSecret();
  if (!secret) return null;
  const payload = Buffer.from(
    JSON.stringify({
      objectPath,
      contentType: contentType || 'application/octet-stream',
      exp: expMs,
    }),
    'utf8',
  );
  const payloadB64 = payload.toString('base64url');
  const sig = crypto
    .createHmac('sha256', secret)
    .update(payloadB64)
    .digest('base64url');
  return `${payloadB64}.${sig}`;
}

function parseAndVerifyAttachmentStreamTicket(ticket) {
  const secret = getAttachmentStreamSigningSecret();
  if (!secret || !ticket || typeof ticket !== 'string') return null;
  const dot = ticket.lastIndexOf('.');
  if (dot <= 0) return null;
  const payloadB64 = ticket.slice(0, dot);
  const sig = ticket.slice(dot + 1);
  const expectedSig = crypto
    .createHmac('sha256', secret)
    .update(payloadB64)
    .digest('base64url');
  let a;
  let b;
  try {
    a = Buffer.from(sig, 'base64url');
    b = Buffer.from(expectedSig, 'base64url');
  } catch (_) {
    return null;
  }
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let data;
  try {
    data = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
  if (!data || typeof data.objectPath !== 'string' || typeof data.exp !== 'number') {
    return null;
  }
  if (Date.now() > data.exp) return null;
  if (!isAllowedProjectAttachmentObjectPath(data.objectPath)) return null;
  return {
    objectPath: data.objectPath.trim().replace(/^\/+/, ''),
    contentType:
      typeof data.contentType === 'string' && data.contentType.trim()
        ? data.contentType.trim()
        : 'application/octet-stream',
  };
}

function getFirebaseStorageBucketName() {
  const fromEnv = (process.env.FIREBASE_STORAGE_BUCKET || '').trim();
  if (fromEnv) return fromEnv;
  if (FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
      if (sa.project_id) return `${sa.project_id}.firebasestorage.app`;
    } catch (_) {}
  }
  return '';
}

function isAllowedProjectAttachmentObjectPath(p) {
  const s = String(p || '').trim().replace(/^\/+/, '');
  if (!s || s.includes('..')) return false;
  return /^project_tracker\/users\/[^/]+\/(task_attachments|subtask_attachments)\/[^/]+\/.+$/i.test(
    s,
  );
}

function extractUploaderUidFromAttachmentPath(objectPath) {
  const m = String(objectPath || '')
    .trim()
    .match(/^project_tracker\/users\/([^/]+)\//i);
  return m ? m[1] : null;
}

function metadataMatchesStaffKey(gcsMetadata, staffKey) {
  if (!staffKey) return false;
  const nested = gcsMetadata && gcsMetadata.metadata;
  const custom =
    nested && typeof nested === 'object' ? nested : {};
  for (let i = 0; i < 10; i++) {
    const k = `m${i}`;
    const v = custom[k];
    if (typeof v === 'string' && v === staffKey) return true;
  }
  return false;
}

function canReadAttachmentObject(sessionUid, staffKey, objectPath, gcsMetadata) {
  const uploaderUid = extractUploaderUidFromAttachmentPath(objectPath);
  if (!uploaderUid) return false;
  if (sessionUid === uploaderUid) return true;
  return metadataMatchesStaffKey(gcsMetadata, staffKey);
}

async function handleAttachmentOpenSession(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (!firebaseAdmin) {
    sendJson(req, res, 503, { error: 'Firebase Admin not configured' });
    return;
  }
  const bucketName = getFirebaseStorageBucketName();
  if (!bucketName) {
    sendJson(req, res, 503, { error: 'FIREBASE_STORAGE_BUCKET or project_id missing' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  let body;
  try {
    body = await readBody(req);
  } catch (_) {
    sendJson(req, res, 400, { error: 'Invalid JSON' });
    return;
  }
  const objectPath = String(body.objectPath || '')
    .trim()
    .replace(/^\/+/, '');
  if (!isAllowedProjectAttachmentObjectPath(objectPath)) {
    sendJson(req, res, 400, { error: 'Invalid object path' });
    return;
  }
  const bucket = firebaseAdmin.storage().bucket(bucketName);
  let meta;
  try {
    [meta] = await bucket.file(objectPath).getMetadata();
  } catch (e) {
    sendJson(req, res, 404, { error: 'Not found' });
    return;
  }
  if (!canReadAttachmentObject(session.uid, session.staffKey, objectPath, meta)) {
    sendJson(req, res, 403, { error: 'Forbidden' });
    return;
  }
  const contentType =
    (meta.contentType && String(meta.contentType).trim()) ||
    'application/octet-stream';
  const exp = Date.now() + ATTACHMENT_STREAM_TTL_MS;
  const ticket = createAttachmentStreamTicket(objectPath, contentType, exp);
  if (!ticket) {
    sendJson(req, res, 503, {
      error:
        'Set ATTACHMENT_STREAM_SIGNING_SECRET (or CRON_SECRET) on the server for attachment streaming.',
    });
    return;
  }
  const qs = new URLSearchParams({ ticket }).toString();
  sendJson(req, res, 200, {
    path: `/api/attachment/stream?${qs}`,
    expiresInSec: Math.floor(ATTACHMENT_STREAM_TTL_MS / 1000),
  });
}

async function handleAttachmentStream(req, res) {
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  if (url.pathname !== '/api/attachment/stream' || req.method !== 'GET') {
    sendJson(req, res, 404, { error: 'Not found' });
    return;
  }
  const authSession = await verifyFirebaseToken(req.headers.authorization);
  if (!authSession) {
    sendJson(req, res, 401, {
      error: 'Authorization required',
      message: 'Send Authorization: Bearer <Firebase ID token> when opening attachments.',
    });
    return;
  }
  const ticket = url.searchParams.get('ticket');
  const sess = ticket ? parseAndVerifyAttachmentStreamTicket(ticket) : null;
  if (!sess) {
    sendJson(req, res, 410, {
      error: 'Link invalid or expired. Open the file again from the app.',
    });
    return;
  }
  if (!firebaseAdmin) {
    sendJson(req, res, 503, { error: 'Firebase Admin not configured' });
    return;
  }
  const bucketName = getFirebaseStorageBucketName();
  if (!bucketName) {
    sendJson(req, res, 503, { error: 'Storage bucket not configured' });
    return;
  }
  const bucket = firebaseAdmin.storage().bucket(bucketName);
  let liveMeta;
  try {
    [liveMeta] = await bucket.file(sess.objectPath).getMetadata();
  } catch (_) {
    sendJson(req, res, 404, { error: 'Not found' });
    return;
  }
  if (
    !canReadAttachmentObject(
      authSession.uid,
      authSession.staffKey,
      sess.objectPath,
      liveMeta,
    )
  ) {
    sendJson(req, res, 403, { error: 'Forbidden' });
    return;
  }
  const file = bucket.file(sess.objectPath);
  const readStream = file.createReadStream();
  const contentType =
    (liveMeta.contentType && String(liveMeta.contentType).trim()) ||
    sess.contentType ||
    'application/octet-stream';
  const headers = {
    'Content-Type': contentType,
    'Cache-Control': 'private, no-store',
    'X-Content-Type-Options': 'nosniff',
  };
  res.writeHead(200, { ...buildCorsHeaders(req), ...headers });
  readStream.on('error', (err) => {
    console.error('attachment stream:', err);
    if (!res.writableEnded) {
      res.destroy();
    }
  });
  readStream.pipe(res);
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

/**
 * `task.create_by` may be `staff.id` (uuid) or `staff.app_id` (matches Flutter insert resolution).
 */
async function fetchStaffRowForCreateBy(supabaseClient, createByRaw) {
  const key = String(createByRaw || '').trim();
  if (!key) return { data: null, error: null };
  const byId = await supabaseClient
    .from('staff')
    .select('id, email, name, display_name')
    .eq('id', key)
    .maybeSingle();
  if (byId.error) return { data: null, error: byId.error };
  if (byId.data) return { data: byId.data, error: null };
  const byApp = await supabaseClient
    .from('staff')
    .select('id, email, name, display_name')
    .eq('app_id', key)
    .maybeSingle();
  if (byApp.error) return { data: null, error: byApp.error };
  return { data: byApp.data || null, error: null };
}

/**
 * Prefer `staff.email`; if empty, use any `app_users.email` linked to `staff.id` (Firebase users often only have the latter).
 */
async function resolveStaffEmailForNotifications(supabaseClient, staffRow) {
  const direct = String(staffRow?.email || '').trim();
  if (direct) return direct;
  const sid = String(staffRow?.id || '').trim();
  if (!sid) return '';
  const { data: rows, error } = await supabaseClient
    .from('app_users')
    .select('email')
    .eq('staff_id', sid)
    .limit(5);
  if (error) return '';
  for (const r of rows || []) {
    const e = String(r?.email || '').trim();
    if (e) return e;
  }
  return '';
}

/**
 * True when [sessionEmailNorm] matches `staff.email` or any `app_users.email` for `staff.id`
 * (Firebase sign-in email often lives on `app_users`, not `staff.email`).
 */
async function sessionEmailBelongsToStaffRow(supabaseClient, staffRow, sessionEmailNorm) {
  const want = (sessionEmailNorm || '').trim().toLowerCase();
  if (!want) return false;
  const direct = String(staffRow?.email || '').trim().toLowerCase();
  if (direct && direct === want) return true;
  const sid = String(staffRow?.id || '').trim();
  if (!sid) return false;
  const { data: rows, error } = await supabaseClient
    .from('app_users')
    .select('email')
    .eq('staff_id', sid)
    .limit(20);
  if (error) return false;
  for (const r of rows || []) {
    const e = String(r?.email || '').trim().toLowerCase();
    if (e && e === want) return true;
  }
  return false;
}

async function handleApiMe(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized', message: 'Invalid or missing Firebase token' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
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
      sendJson(req, res, 200, { role: null, staffId: null, staffAppId: null, assignableStaff: [] });
      return;
    }
    sendJson(req, res, 200, {
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
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiAssignableStaff(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  try {
    const byEmail = await fetchProfileByEmail(session.email);
    const uidForAssignable = byEmail?.firebase_uid_for_rpc || session.uid;
    const { data, error } = await supabase.rpc('get_assignable_staff', {
      p_firebase_uid: uidForAssignable,
    });
    if (error) throw error;
    sendJson(req, res, 200, { assignableStaff: data || [] });
  } catch (e) {
    console.error('get_assignable_staff:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
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
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return null;
  }
  if ((session.email || '').toLowerCase() !== ADMIN_EMAIL) {
    sendJson(req, res, 403, { error: 'Forbidden', message: 'Admin only' });
    return null;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
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
    sendJson(req, res, 200, {
      teams: teams.data || [],
      roles: roles.data || [],
      staff: staff.data || [],
      appUsers: appUsers.data || [],
      userRoleMapping: urm.data || [],
      teamMembers: tm.data || [],
      subordinateMapping: sub.data || [],
    });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminUpsertUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { firebase_uid, email, display_name, staff_app_id, role_app_id } = body;
    if (!firebase_uid || !email || !role_app_id) {
      sendJson(req, res, 400, { error: 'firebase_uid, email, role_app_id required' });
      return;
    }
    let staffId = null;
    if (staff_app_id) {
      const { data: s } = await supabase.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
      staffId = s?.id || null;
    }
    const { data: roleRow } = await supabase.from('roles').select('id').eq('app_id', role_app_id).maybeSingle();
    if (!roleRow) {
      sendJson(req, res, 400, { error: 'Invalid role_app_id' });
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
    sendJson(req, res, 200, { ok: true, appUserId: userRow.id });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminDeleteUser(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  const url = new URL(req.url || '/', `http://${req.headers.host}`);
  const id = url.pathname.split('/').pop();
  if (!id) {
    sendJson(req, res, 400, { error: 'Missing id' });
    return;
  }
  try {
    await supabase.from('user_role_mapping').delete().eq('app_user_id', id);
    await supabase.from('app_users').delete().eq('id', id);
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminUpsertTeam(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { name, app_id } = body;
    if (!name || !app_id) {
      sendJson(req, res, 400, { error: 'name, app_id required' });
      return;
    }
    const { error } = await supabase.from('teams').upsert(
      { name, app_id },
      { onConflict: 'app_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminTeamMember(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { team_app_id, staff_app_id, role } = body;
    if (!team_app_id || !staff_app_id || !role) {
      sendJson(req, res, 400, { error: 'team_app_id, staff_app_id, role required' });
      return;
    }
    const { data: t } = await supabase.from('teams').select('id').eq('app_id', team_app_id).maybeSingle();
    const { data: s } = await supabase.from('staff').select('id').eq('app_id', staff_app_id).maybeSingle();
    if (!t || !s) {
      sendJson(req, res, 400, { error: 'Team or staff not found' });
      return;
    }
    const { error } = await supabase.from('team_members').upsert(
      { team_id: t.id, staff_id: s.id, role },
      { onConflict: 'team_id,staff_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleAdminSubordinate(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  try {
    const body = await readBody(req);
    const { supervisor_staff_app_id, subordinate_staff_app_id } = body;
    if (!supervisor_staff_app_id || !subordinate_staff_app_id) {
      sendJson(req, res, 400, { error: 'supervisor_staff_app_id, subordinate_staff_app_id required' });
      return;
    }
    const { data: sup } = await supabase.from('staff').select('id').eq('app_id', supervisor_staff_app_id).maybeSingle();
    const { data: sub } = await supabase.from('staff').select('id').eq('app_id', subordinate_staff_app_id).maybeSingle();
    if (!sup || !sub) {
      sendJson(req, res, 400, { error: 'Staff not found' });
      return;
    }
    const { error } = await supabase.from('subordinate_mapping').upsert(
      { supervisor_staff_id: sup.id, subordinate_staff_id: sub.id },
      { onConflict: 'supervisor_staff_id,subordinate_staff_id' },
    );
    if (error) throw error;
    sendJson(req, res, 200, { ok: true });
  } catch (e) {
    sendJson(req, res, 500, { error: e.message });
  }
}

async function handleApiTeams(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
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
    sendJson(req, res, 200, { teams });
  } catch (e) {
    console.error('handleApiTeams:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleApiStaff(req, res) {
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
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
    sendJson(req, res, 200, { staff });
  } catch (e) {
    console.error('handleApiStaff:', e);
    sendJson(req, res, 500, { error: 'Server error', message: e.message });
  }
}

async function handleHealth(req, res) {
  sendJson(req, res, 200, {
    ok: true,
    message: 'Project Tracker backend',
    timestamp: new Date().toISOString(),
    // Safe diagnostics (no secrets). If supabaseConfigured is false, check Railway Variables on THIS service.
    firebaseConfigured: !!firebaseAdmin,
    supabaseConfigured: !!supabase,
    mailgunConfigured: !!(MAILGUN_API_KEY && MAILGUN_DOMAIN),
    urgentReminderCronEnabled: process.env.DISABLE_INTERNAL_URGENT_CRON !== 'true',
    cronSecretConfigured: CRON_SECRET.length > 0,
    env: {
      supabaseUrlSet: SUPABASE_URL.length > 0,
      supabaseServiceRoleKeySet: SUPABASE_SERVICE_ROLE_KEY.length > 0,
    },
  });
}

/**
 * Single recipient for Mailgun: trim, lowercase, first address if comma/semicolon-separated.
 */
function normalizeRecipientEmail(raw) {
  let s = String(raw ?? '').trim();
  if (!s) return '';
  if (/[,;]/.test(s)) {
    s = s.split(/[,;]/)[0].trim();
  }
  const firstToken = (s.split(/\s+/)[0] || '').trim();
  return firstToken.toLowerCase();
}

function formatMailgunFailure(r) {
  const base = r.error || 'failed';
  const d = r.detail ? ` — ${String(r.detail).slice(0, 450)}` : '';
  return `${base}${d}`;
}

/**
 * Send via Mailgun HTTP API (application/x-www-form-urlencoded).
 * @param [opts.html] HTML body (optional; plain [text] fallback for clients)
 * @param [opts.from] Full From header (must be allowed on the Mailgun domain)
 * @param [opts.replyTo] Sets h:Reply-To
 * @returns {{ ok: true, id: string } | { ok: false, error: string, detail?: string }}
 */
async function sendMailgun({ to, subject, text, html, from: fromOverride, replyTo, cc }) {
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    return { ok: false, error: 'Mailgun not configured (MAILGUN_API_KEY / MAILGUN_DOMAIN)' };
  }
  const toAddr = normalizeRecipientEmail(to);
  if (!toAddr || !toAddr.includes('@')) {
    return {
      ok: false,
      error: 'Missing or invalid recipient email (to)',
      resolvedTo: toAddr || '',
    };
  }
  const from =
    fromOverride ||
    MAILGUN_FROM ||
    `postmaster@${MAILGUN_DOMAIN}`;
  const url = `${MAILGUN_BASE_URL}/v3/${encodeURIComponent(MAILGUN_DOMAIN)}/messages`;
  const auth = Buffer.from(`api:${MAILGUN_API_KEY}`).toString('base64');
  const body = new URLSearchParams({ from, to: toAddr, subject });
  const ccAddr = normalizeRecipientEmail(cc);
  if (ccAddr && ccAddr.includes('@')) {
    body.append('cc', ccAddr);
  }
  if (html) {
    body.append('html', html);
    body.append('text', text || '');
  } else {
    body.append('text', text || '');
  }
  const rt = (replyTo || '').trim();
  if (rt) {
    body.append('h:Reply-To', rt);
  }
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    });
    const raw = await r.text();
    if (!r.ok) {
      console.error('[mailgun] send failed', r.status, url, raw.slice(0, 800));
      return {
        ok: false,
        error: `Mailgun HTTP ${r.status}`,
        detail: raw.slice(0, 500),
        resolvedTo: toAddr,
      };
    }
    let id = '';
    try {
      const j = JSON.parse(raw);
      id = (j && j.id) || '';
    } catch (_) {}
    return { ok: true, id, resolvedTo: toAddr };
  } catch (e) {
    return { ok: false, error: e.message || String(e), resolvedTo: toAddr };
  }
}

/** Admin-only: POST body `{ "to": "you@example.com" }` — sends one test email (sandbox: recipient must be authorized in Mailgun). */
async function handleAdminTestMailgun(req, res) {
  const session = await requireAdmin(req, res);
  if (!session) return;
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  try {
    const body = await readBody(req);
    const to = (body.to || '').trim();
    if (!to) {
      sendJson(req, res, 400, { error: 'JSON body must include "to" (recipient email)' });
      return;
    }
    const result = await sendMailgun({
      to,
      subject: 'Project Tracker — Mailgun test (Railway production)',
      text: `Test message sent at ${new Date().toISOString()}\n\nIf you use a Mailgun sandbox domain, the recipient must be listed as an authorized recipient in Mailgun.`,
    });
    if (result.ok) {
      sendJson(req, res, 200, { ok: true, mailgunId: result.id || null });
    } else {
      sendJson(req, res, 502, { ok: false, error: result.error, detail: result.detail });
    }
  } catch (e) {
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function mailSubjectSingleLine(s) {
  return String(s)
    .replace(/[\r\n\u2028\u2029]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Deduped staff UUIDs from task.assignee_01 … assignee_10. */
function collectTaskAssigneeStaffIds(taskRow) {
  const assigneeIds = [];
  const seen = new Set();
  for (let i = 1; i <= 10; i++) {
    const key = `assignee_${String(i).padStart(2, '0')}`;
    const v = taskRow[key];
    if (v == null) continue;
    const u = String(v).trim();
    if (!u || seen.has(u)) continue;
    seen.add(u);
    assigneeIds.push(u);
  }
  return assigneeIds;
}

/**
 * Default recipients for task-updated emails: assignee_01..10 with values plus
 * create_by, deduped (normalized key -> canonical id string).
 * @param {Record<string, unknown>} taskRow
 * @returns {Map<string, string>}
 */
function buildTaskUpdatedDefaultRecipientStaffIds(taskRow) {
  const recipientByNorm = new Map();
  for (const id of collectTaskAssigneeStaffIds(taskRow)) {
    const raw = String(id).trim();
    if (!raw) continue;
    const key = raw.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
  }
  const createBy = (taskRow.create_by || '').toString().trim();
  if (createBy) {
    const key = createBy.toLowerCase();
    if (!recipientByNorm.has(key)) recipientByNorm.set(key, createBy);
  }
  return recipientByNorm;
}

/** Same slot layout as [collectTaskAssigneeStaffIds] for `public.subtask`. */
function collectSubtaskAssigneeStaffIds(subtaskRow) {
  return collectTaskAssigneeStaffIds(subtaskRow);
}

/**
 * Task-comment email to task creator only (`handleNotifyTaskComment`).
 * @param {{ recipientDisplayName: string, commentDescription: string, taskName: string, taskUrl: string }} p
 */
function buildTaskCommentCreatorEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDesc = escapeHtml(desc);
  const safeTaskUrlAttr = escapeHtml(p.taskUrl);
  const safeTitle = escapeHtml(p.taskName);
  const safeLandingHref = escapeHtml(TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added – ${safeDesc}</span><br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildTaskCommentCreatorEmailText(p) {
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is added – ${desc}

${p.taskName}
${p.taskUrl}

Project Tracker
${TASK_UPDATE_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/**
 * Task comment **edited** notify (`handleNotifyTaskEditedComment`): Hi + edited line + task link +
 * Updated by / at + Project Tracker; Aptos 16px.
 *
 * @param {{ recipientDisplayName: string, commentDescription: string, taskName: string, taskUrl: string, updaterDisplayName: string, updatedAtLine: string }} p
 */
function buildTaskCommentEditedEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDescHtml = desc
    .split(/\r?\n/)
    .map((line) => escapeHtml(line))
    .join('<br>');
  const safeTaskUrlAttr = escapeHtml(p.taskUrl);
  const safeTitle = escapeHtml(p.taskName);
  const safeUpdater = escapeHtml(p.updaterDisplayName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is edited – ${safeDescHtml}</span><br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildTaskCommentEditedEmailText(p) {
  let desc = String(p.commentDescription || '').trim();
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is edited – ${desc}

${p.taskName}
${p.taskUrl}

Updated by: ${p.updaterDisplayName}

Updated at: ${p.updatedAtLine}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/**
 * “Project Tracker” link in sub-task comment → creator emails (strict product URL, no trailing path).
 */
const SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF = 'https://projecttracker.hku.hk';

/** En dash (U+2013) after “Comment is added”, per product template. */
const SUBTASK_COMMENT_ADDED_LINE_EN_DASH = '\u2013';

/**
 * Plain text for email from `subtask_comment.description` (`text` column; also accepts JSON
 * `{"value":"..."}` when stored as a string or parsed object, matching `{description.value}`).
 */
function subtaskCommentDescriptionPlainText(raw) {
  if (raw == null || raw === '') return '';
  if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
    if (Object.prototype.hasOwnProperty.call(raw, 'value')) {
      return String(raw.value ?? '').trim();
    }
  }
  const s = String(raw).trim();
  if (s.startsWith('{') && s.includes('"value"')) {
    try {
      const o = JSON.parse(s);
      if (o && typeof o === 'object' && o.value != null) {
        return String(o.value).trim();
      }
    } catch (_) {
      /* use full string */
    }
  }
  return s;
}

/**
 * Sub-task comment email to sub-task creator only (`handleNotifySubtaskComment`).
 * Subject: `{comment author} comments on sub-task "{subtask.subtask_name}"`.
 * Body: Hi {creator staff.display_name}; Comment is added – {description}; bold+underlined
 * {subtask.subtask_name} → `subtaskWebAppUrl(subtask.id)`; “Project Tracker” → product URL; Aptos 16px.
 *
 * @param {{ recipientDisplayName: string, commentDescription: string, subtaskName: string, subtaskUrl: string }} p
 */
function buildSubtaskCommentCreatorEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let desc = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDesc = escapeHtml(desc);
  const safeSubtaskUrlAttr = escapeHtml(p.subtaskUrl);
  const safeTitle = escapeHtml(p.subtaskName);
  const safeLandingHref = escapeHtml(SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
Comment is added ${SUBTASK_COMMENT_ADDED_LINE_EN_DASH} ${safeDesc}<br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildSubtaskCommentCreatorEmailText(p) {
  let desc = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!desc) desc = '(no text)';
  if (desc.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    desc = `${desc.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is added ${SUBTASK_COMMENT_ADDED_LINE_EN_DASH} ${desc}

${p.subtaskName}
${p.subtaskUrl}

Project Tracker
${SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF}`;
}

/**
 * Sub-task comment **edited** notify (`handleNotifySubtaskEditedComment`): Hi + edited line + sub-task link +
 * Updated by / at + Project Tracker; Aptos 16px. Description uses [subtaskCommentDescriptionPlainText].
 *
 * @param {{ recipientDisplayName: string, commentDescription: unknown, subtaskName: string, subtaskUrl: string, updaterDisplayName: string, updatedAtLine: string }} p
 */
function buildSubtaskCommentEditedEmailHtml(p) {
  const safeHi = escapeHtml(p.recipientDisplayName);
  let descPlain = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!descPlain) descPlain = '(no text)';
  if (descPlain.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    descPlain = `${descPlain.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  const safeDescHtml = descPlain
    .split(/\r?\n/)
    .map((line) => escapeHtml(line))
    .join('<br>');
  const safeSubtaskUrlAttr = escapeHtml(p.subtaskUrl);
  const safeTitle = escapeHtml(p.subtaskName);
  const safeUpdater = escapeHtml(p.updaterDisplayName);
  const safeUpdatedAt = escapeHtml(p.updatedAtLine);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">Hi ${safeHi},<br><br>
<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is edited – ${safeDescHtml}</span><br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
Updated by: ${safeUpdater}<br><br>
Updated at: ${safeUpdatedAt}<br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildSubtaskCommentEditedEmailText(p) {
  let descPlain = subtaskCommentDescriptionPlainText(p.commentDescription);
  if (!descPlain) descPlain = '(no text)';
  if (descPlain.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
    descPlain = `${descPlain.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
  }
  return `Hi ${p.recipientDisplayName},

Comment is edited – ${descPlain}

${p.subtaskName}
${p.subtaskUrl}

Updated by: ${p.updaterDisplayName}

Updated at: ${p.updatedAtLine}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/** Formats task.update_date (timestamptz) as YYYY-MM-DD in Asia/Hong_Kong. */
function formatUpdateDateYYYYMMDD(raw) {
  if (raw == null || raw === '') return '—';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Hong_Kong' });
}

/** Formats task.update_date as `yyyy-mm-dd hh:mm` (wall clock in Asia/Hong_Kong). */
function formatUpdateDateTimeYmdHm(raw) {
  if (raw == null || raw === '') return '—';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return '—';
  const datePart = d.toLocaleDateString('en-CA', { timeZone: 'Asia/Hong_Kong' });
  const timeParts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Hong_Kong',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  let hh = '';
  let mm = '';
  for (const p of timeParts) {
    if (p.type === 'hour') hh = p.value.padStart(2, '0');
    if (p.type === 'minute') mm = p.value.padStart(2, '0');
  }
  const hm = hh && mm ? `${hh}:${mm}` : '—';
  return `${datePart} ${hm}`;
}

/** Formats task.due_date as YYYY-MM-DD for emails (avoids timezone shift on date-only strings). */
function formatTaskDueDateYYYYMMDD(raw) {
  if (raw == null || raw === '') return '—';
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return '—';
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${day}`;
}

function cronSecretFromRequest(req) {
  const headers = req.headers || {};
  const h =
    headers['x-cron-secret'] ||
    headers['X-Cron-Secret'] ||
    (() => {
      const k = Object.keys(headers).find((n) => n.toLowerCase() === 'x-cron-secret');
      return k ? headers[k] : '';
    })();
  return String(h || '').trim();
}

function verifyCronSecret(req) {
  if (!CRON_SECRET) return false;
  const h = cronSecretFromRequest(req);
  const auth = String(req.headers.authorization || '');
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  return h === CRON_SECRET || bearer === CRON_SECRET;
}

/** Hong Kong calendar day bounds (ms) for a date/timestamptz from the DB. */
function hkDayStartEndMs(raw) {
  if (raw == null || raw === '') return null;
  const s = String(raw).trim();
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const dayStr = `${m[1]}-${m[2]}-${m[3]}`;
    return {
      startMs: new Date(`${dayStr}T00:00:00+08:00`).getTime(),
      endMs: new Date(`${dayStr}T23:59:59.999+08:00`).getTime(),
    };
  }
  const t = new Date(s).getTime();
  if (Number.isNaN(t)) return null;
  const d = new Date(s);
  const y = d.getUTCFullYear();
  const mo = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  const dayStr = `${y}-${mo}-${day}`;
  return {
    startMs: new Date(`${dayStr}T00:00:00+08:00`).getTime(),
    endMs: new Date(`${dayStr}T23:59:59.999+08:00`).getTime(),
  };
}

/** True when [now] is at or past 80% of the interval from start-date (HK 00:00) to due-date (HK 23:59:59.999). */
function hasReachedEightyPercentWindow(startRaw, dueRaw, nowMs) {
  const startB = hkDayStartEndMs(startRaw);
  const dueB = hkDayStartEndMs(dueRaw);
  if (!startB || !dueB) return false;
  const t0 = startB.startMs;
  const t1 = dueB.endMs;
  const total = t1 - t0;
  if (total <= 0) return false;
  const elapsed = nowMs - t0;
  return elapsed / total >= 0.8;
}

function taskStatusBlocksUrgentReminder(statusRaw) {
  const s = String(statusRaw || '')
    .trim()
    .toLowerCase();
  return s === 'completed' || s === 'deleted';
}

/** Task ids whose parent row is soft-deleted — sub-task reminder emails must not run until the task is undone. */
async function fetchDeletedParentTaskIdSet(supabaseClient) {
  const { data, error } = await supabaseClient.from('task').select('id,status');
  if (error || !data) return new Set();
  const set = new Set();
  for (const row of data) {
    const st = String(row.status ?? '')
      .trim()
      .toLowerCase();
    if (st === 'deleted') {
      const id = String(row.id || '').trim();
      if (id) set.add(id);
    }
  }
  return set;
}

/**
 * AssigneeOverdueReminder + Subtask_AssigneeOverdueReminder — after `isCalendarPastDue`
 * (HK **today** > due_date). Same daily cron as other jobs: **09:00 Asia/Hong_Kong** (UTC+8).
 *
 * Task / sub-task rows:
 * - **Pending** (and null/empty, treated like Pending): send.
 * - **Submitted**: do not send.
 * - **Returned**: send.
 * - Any other value (e.g. Accepted): do not send.
 */
function submissionAllowsAssigneeOverdueReminder(submissionRaw) {
  const s =
    submissionRaw == null ? '' : String(submissionRaw).trim().toLowerCase();
  if (s === 'submitted') return false;
  if (s === 'pending' || s === 'returned' || s === '') return true;
  return false;
}

/** Today's calendar date (YYYY-MM-DD) in Asia/Hong_Kong. */
function hkTodayYyyyMmDd() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Hong_Kong',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

/** Due date as YYYY-MM-DD for calendar comparison, or null. */
function dueDateYyyyMmDdOnly(raw) {
  if (raw == null || raw === '') return null;
  const s = formatTaskDueDateYYYYMMDD(raw);
  if (!s || s === '—') return null;
  return s;
}

function isCalendarOnOrBeforeDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd <= d;
}

/** Urgent 80% emails run only before the due calendar day (not on due date). */
function isCalendarStrictlyBeforeDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd < d;
}

function isCalendarDueToday(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd === d;
}

function isCalendarPastDue(todayYmd, dueRaw) {
  const d = dueDateYyyyMmDdOnly(dueRaw);
  if (!d) return false;
  return todayYmd > d;
}

/**
 * After the due calendar date (HK), reset reminder flags so rows are clean.
 */
async function resetUrgentReminderForPastDueTasks(supabaseClient, todayYmd, summary) {
  const { data: rows, error } = await supabaseClient
    .from('task')
    .select(
      'id, due_date, urgent_reminder_sent, urgent_reminder_last_sent_on, due_today_reminder_sent_on, creator_due_today_reminder_sent_on, creator_urgent_reminder_last_sent_on',
    )
    .not('due_date', 'is', null);
  if (error) {
    summary.errors.push(`past-due cleanup: ${error.message}`);
    return;
  }
  for (const row of rows || []) {
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const sent = row.urgent_reminder_sent === true;
    const hasLast = row.urgent_reminder_last_sent_on != null && row.urgent_reminder_last_sent_on !== '';
    const hasDueToday =
      row.due_today_reminder_sent_on != null && row.due_today_reminder_sent_on !== '';
    const hasCreatorDue =
      row.creator_due_today_reminder_sent_on != null && row.creator_due_today_reminder_sent_on !== '';
    const hasCreatorUrgent =
      row.creator_urgent_reminder_last_sent_on != null && row.creator_urgent_reminder_last_sent_on !== '';
    if (!sent && !hasLast && !hasDueToday && !hasCreatorDue && !hasCreatorUrgent) continue;
    const id = String(row.id || '').trim();
    if (!id) continue;
    const { error: uErr } = await supabaseClient
      .from('task')
      .update({
        urgent_reminder_sent: false,
        urgent_reminder_last_sent_on: null,
        due_today_reminder_sent_on: null,
        creator_due_today_reminder_sent_on: null,
        creator_urgent_reminder_last_sent_on: null,
      })
      .eq('id', id);
    if (uErr) {
      summary.errors.push(`past-due reset ${id}: ${uErr.message}`);
    } else {
      summary.tasksResetPastDue += 1;
    }
  }
}

function buildUrgentTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have an <b>upcoming</b> task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have an upcoming task due.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

function buildDueTodayTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a task <b>due today</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a task due today.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today reminder for task creator only ([creator_due_today_reminder_sent_on]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.display_name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.display_name)
 */
function buildCreatorDueTodayTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has task due today.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has task due today.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today (HK) — sub-task creator only ([subtask_creator_due_today_reminder_sent_on]).
 * @param {string} recipientDisplayName — creator greeting (`create_by` → staff.display_name, else name)
 * @param {string} picDisplayName — PIC line (`subtask.pic` → staff.display_name, else name)
 */
function buildCreatorDueTodaySubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const safeLanding = escapeHtml(SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF);
  const html = `Hi ${safeRecipient}, <br><br>
${safePic} has sub-task due today.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has sub-task due today.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${SUBTASK_COMMENT_NOTIFY_PROJECT_TRACKER_HREF}`;
  return { html, text };
}

/**
 * Overdue (HK) — task creator ([CreatorOverdueReminder]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.display_name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.display_name)
 */
function buildCreatorOverdueTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has a task overdue.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has a task overdue.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/** Overdue (HK) — task assignees. */
function buildAssigneeOverdueTaskReminderEmail(displayName, taskName, taskUrl, dueYmd) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = OVERDUE_REMINDER_LANDING_HREF;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a task <b>overdue</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a task overdue.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Overdue (HK) — sub-task creator ([Subtask_CreatorOverdueReminder]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.display_name)
 * @param {string} picDisplayName — PIC (`subtask.pic` → staff.display_name)
 */
function buildCreatorOverdueSubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has a sub-task overdue.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has a sub-task overdue.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/** Overdue (HK) — sub-task assignees. */
function buildAssigneeOverdueSubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = OVERDUE_REMINDER_LANDING_HREF;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a sub-task <b>overdue</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: <span style="color:red;">${safeDue}</span><br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a sub-task overdue.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — creator only. Subject/body format fixed for product spec.
 * @param {string} recipientDisplayName — task creator (`create_by` → staff.display_name)
 * @param {string} picDisplayName — PIC (`task.pic` → staff.display_name)
 */
function buildCreatorUrgentTaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  taskName,
  taskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(taskName);
  const safeUrl = escapeHtml(taskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient},<br><br>
${safePic} has an <b>upcoming</b> task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName},

${picDisplayName} has an upcoming task due.

${taskName}
${taskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — sub-task creator only ([runCreatorUrgentSubtaskReminderJob]).
 * @param {string} recipientDisplayName — creator (`create_by` → staff.display_name)
 * @param {string} picDisplayName — PIC (`subtask.pic` → staff.display_name)
 */
function buildCreatorUrgentSubtaskReminderEmail(
  recipientDisplayName,
  picDisplayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeRecipient = escapeHtml(recipientDisplayName);
  const safePic = escapeHtml(picDisplayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeRecipient}.<br><br>
${safePic} has an <b>upcoming</b> sub-task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${recipientDisplayName}.

${picDisplayName} has an upcoming sub-task due.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * 80% window — sub-task assignees (assignee_01..10). Subject/body format fixed for product spec.
 */
function buildAssigneeUrgentSubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have an <b>upcoming</b> sub-task due.<br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have an upcoming sub-task due.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * Due-today (HK) — sub-task assignees. Subject/body format fixed for product spec.
 */
function buildAssigneeDueTodaySubtaskReminderEmail(
  displayName,
  subtaskName,
  subtaskUrl,
  dueYmd,
) {
  const safeName = escapeHtml(displayName);
  const safeTitle = escapeHtml(subtaskName);
  const safeUrl = escapeHtml(subtaskUrl);
  const safeDue = escapeHtml(dueYmd);
  const landing = `${String(PROJECT_TRACKER_LANDING_URL || 'https://projecttracker.hku.hk').replace(/\/$/, '')}/`;
  const safeLanding = escapeHtml(landing);
  const html = `Hi ${safeName}. You have a sub-task <b>due today</b><br><br>
<b><u><a href="${safeUrl}" style="color:#1565C0;">${safeTitle}</a></u></b><br><br>
Due Date: ${safeDue}<br><br>
<a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a>`;
  const text = `Hi ${displayName}. You have a sub-task due today.

${subtaskName}
${subtaskUrl}

Due Date: ${dueYmd}

Project Tracker
${landing}`;
  return { html, text };
}

function subtaskStatusBlocksUrgentReminder(statusRaw) {
  const s = String(statusRaw || '')
    .trim()
    .toLowerCase();
  return s === 'completed' || s === 'deleted';
}

/**
 * After the due calendar date (HK), reset sub-task reminder columns.
 */
async function resetUrgentReminderForPastDueSubtasks(supabaseClient, todayYmd, summary) {
  const { data: rows, error } = await supabaseClient
    .from('subtask')
    .select(
      'id, due_date, urgent_reminder_sent, assignee_urgent_reminder_last_sent_on, creator_urgent_reminder_last_sent_on, subtask_creator_due_today_reminder_sent_on, subtask_assignee_due_today_reminder_sent_on',
    )
    .not('due_date', 'is', null);
  if (error) {
    summary.errors.push(`subtask past-due cleanup: ${error.message}`);
    return;
  }
  for (const row of rows || []) {
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    const sent = row.urgent_reminder_sent === true;
    const hasAssigneeLast =
      row.assignee_urgent_reminder_last_sent_on != null &&
      row.assignee_urgent_reminder_last_sent_on !== '';
    const hasLast =
      row.creator_urgent_reminder_last_sent_on != null &&
      row.creator_urgent_reminder_last_sent_on !== '';
    const hasCreatorDueToday =
      row.subtask_creator_due_today_reminder_sent_on != null &&
      row.subtask_creator_due_today_reminder_sent_on !== '';
    const hasAssigneeDueToday =
      row.subtask_assignee_due_today_reminder_sent_on != null &&
      row.subtask_assignee_due_today_reminder_sent_on !== '';
    if (!sent && !hasAssigneeLast && !hasLast && !hasCreatorDueToday && !hasAssigneeDueToday) {
      continue;
    }
    const id = String(row.id || '').trim();
    if (!id) continue;
    const { error: uErr } = await supabaseClient
      .from('subtask')
      .update({
        urgent_reminder_sent: false,
        assignee_urgent_reminder_last_sent_on: null,
        creator_urgent_reminder_last_sent_on: null,
        subtask_creator_due_today_reminder_sent_on: null,
        subtask_assignee_due_today_reminder_sent_on: null,
      })
      .eq('id', id);
    if (uErr) {
      summary.errors.push(`subtask past-due reset ${id}: ${uErr.message}`);
    } else {
      summary.subtasksResetPastDue += 1;
    }
  }
}

/**
 * 80% window — each assignee with assignee_01..10 set gets one Mailgun message per HK day.
 * Uses [urgent_reminder_sent] + [assignee_urgent_reminder_last_sent_on] like task assignee urgent.
 * Runs past-due reset first. **Not** sent when HK today equals [due_date] (assignee due-today uses
 * [runAssigneeDueTodaySubtaskReminderJob] that day instead).
 */
async function runAssigneeUrgentSubtaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    subtasksResetPastDue: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  await resetUrgentReminderForPastDueSubtasks(supabase, todayYmd, summary);

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    if (isCalendarDueToday(todayYmd, row.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, row.due_date)) continue;
    if (!hasReachedEightyPercentWindow(row.start_date, row.due_date, nowMs)) {
      continue;
    }

    const lastAssignee = row.assignee_urgent_reminder_last_sent_on;
    const lastAssigneeStr =
      lastAssignee == null || lastAssignee === ''
        ? null
        : String(lastAssignee).trim().slice(0, 10);
    if (lastAssigneeStr === todayYmd) {
      continue;
    }

    const assigneeIds = collectSubtaskAssigneeStaffIds(row);
    if (assigneeIds.length === 0) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    summary.eligible += 1;
    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        sendResults.push({ staffId, ok: false, skipped: 'staff not found' });
        continue;
      }
      const to = await resolveStaffEmailForNotifications(supabase, staffRow);
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildAssigneeUrgentSubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: mailSubjectSingleLine('You have upcoming sub-tasks due'),
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedMailgun = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedMailgun) {
      const { error: uErr } = await supabase
        .from('subtask')
        .update({
          urgent_reminder_sent: true,
          assignee_urgent_reminder_last_sent_on: todayYmd,
        })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`assignee urgent subtask update ${subtaskId}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * Same 80% window as task creator urgent: email subtask.create_by once per HK day while
 * [isCalendarStrictlyBeforeDue] and [hasReachedEightyPercentWindow]. Uses
 * [creator_urgent_reminder_last_sent_on] only (assignee batch uses [urgent_reminder_sent]).
 * Skips if create_by === assignee_01. **Not** sent when HK today equals [due_date] — that day uses
 * [runCreatorDueTodaySubtaskReminderJob] only.
 */
async function runCreatorUrgentSubtaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    subtasksResetPastDue: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    // HK due date = today: only runCreatorDueTodaySubtaskReminderJob (not this urgent job).
    if (isCalendarDueToday(todayYmd, row.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, row.due_date)) continue;
    if (!hasReachedEightyPercentWindow(row.start_date, row.due_date, nowMs)) {
      continue;
    }

    const lastCreator = row.creator_urgent_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(supabase, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator urgent staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorUrgentSubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName} has an upcoming sub-task due`,
      ),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun subtask creator urgent subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('subtask')
      .update({
        creator_urgent_reminder_last_sent_on: todayYmd,
      })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator urgent update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * Daily urgent emails (09:00 Asia/Hong_Kong + manual POST): send each HK day while
 * 80%–due window applies; [urgent_reminder_last_sent_on] prevents duplicate sends same day.
 * Does not run on the due calendar day (that day uses due-today emails only).
 * Past-due tasks: reset [urgent_reminder_sent] false and clear last_sent_on.
 */
async function runUrgentTaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    tasksResetPastDue: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  await resetUrgentReminderForPastDueTasks(supabase, todayYmd, summary);

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, taskRow.due_date)) continue;
    if (!hasReachedEightyPercentWindow(taskRow.start_date, taskRow.due_date, nowMs)) {
      continue;
    }

    const lastSent = taskRow.urgent_reminder_last_sent_on;
    const lastSentStr =
      lastSent == null || lastSent === ''
        ? null
        : String(lastSent).trim().slice(0, 10);
    if (lastSentStr === todayYmd) {
      continue;
    }

    summary.eligible += 1;
    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await supabase
        .from('staff')
        .select('email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      const to = (staffRow?.email || '').trim();
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildUrgentTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: 'You have upcoming tasks due',
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedMailgun = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedMailgun) {
      const { error: uErr } = await supabase
        .from('task')
        .update({
          urgent_reminder_sent: true,
          urgent_reminder_last_sent_on: todayYmd,
        })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`Update ${taskId}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * Same 80% window as assignee urgent reminders: email task.create_by once per HK day while
 * [isCalendarStrictlyBeforeDue] and [hasReachedEightyPercentWindow]. Uses [creator_urgent_reminder_last_sent_on].
 * Does not run when HK today is the due date (that day uses creator due-today + [creator_due_today_reminder_sent_on]).
 * Skips if create_by === assignee_01.
 */
async function runCreatorUrgentTaskReminderJob() {
  const nowMs = Date.now();
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('start_date', 'is', null)
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    // On the due calendar day (HK), do not run creator urgent — use creator due-today only.
    if (isCalendarDueToday(todayYmd, taskRow.due_date)) continue;
    if (!isCalendarStrictlyBeforeDue(todayYmd, taskRow.due_date)) continue;
    if (!hasReachedEightyPercentWindow(taskRow.start_date, taskRow.due_date, nowMs)) {
      continue;
    }

    const lastCreator = taskRow.creator_urgent_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      supabase,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator urgent staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorUrgentTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s upcoming task due`),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun creator urgent task=${taskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('task')
      .update({ creator_urgent_reminder_last_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator urgent update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * Due-date = today (HK calendar): one batch per task per day to assignees.
 * Runs at 09:00 Asia/Hong_Kong with urgent job; not sent on days covered by urgent-only window.
 */
async function runDueTodayTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (!isCalendarDueToday(todayYmd, taskRow.due_date)) continue;

    const lastDue = taskRow.due_today_reminder_sent_on;
    const lastDueStr =
      lastDue == null || lastDue === ''
        ? null
        : String(lastDue).trim().slice(0, 10);
    if (lastDueStr === todayYmd) {
      continue;
    }

    summary.eligible += 1;
    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await supabase
        .from('staff')
        .select('email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      const to = (staffRow?.email || '').trim();
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildDueTodayTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: 'You have tasks due today',
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedMailgun = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedMailgun) {
      const { error: uErr } = await supabase
        .from('task')
        .update({ due_today_reminder_sent_on: todayYmd })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`due-today update ${taskId}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one batch per sub-task per day to assignee_01..10.
 * Uses [subtask_assignee_due_today_reminder_sent_on]. Skips completed/deleted.
 */
async function runAssigneeDueTodaySubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    if (!isCalendarDueToday(todayYmd, row.due_date)) continue;

    const lastDue = row.subtask_assignee_due_today_reminder_sent_on;
    const lastDueStr =
      lastDue == null || lastDue === ''
        ? null
        : String(lastDue).trim().slice(0, 10);
    if (lastDueStr === todayYmd) {
      continue;
    }

    const assigneeIds = collectSubtaskAssigneeStaffIds(row);
    if (assigneeIds.length === 0) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    summary.eligible += 1;
    const sendResults = [];
    for (const staffId of assigneeIds) {
      const { data: staffRow } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        sendResults.push({ staffId, ok: false, skipped: 'staff not found' });
        continue;
      }
      const to = await resolveStaffEmailForNotifications(supabase, staffRow);
      if (!to) {
        sendResults.push({ staffId, ok: false, skipped: 'no email' });
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;
      const { html, text } = buildAssigneeDueTodaySubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: mailSubjectSingleLine('You have sub-tasks due today'),
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      sendResults.push({ to, ok: r.ok, error: r.ok ? null : r.error });
    }

    const failedMailgun = sendResults.some((x) => !x.ok && !x.skipped);
    if (!failedMailgun) {
      const { error: uErr } = await supabase
        .from('subtask')
        .update({ subtask_assignee_due_today_reminder_sent_on: todayYmd })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`subtask assignee due-today update ${subtaskId}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one email per task to task.create_by (staff).
 * Independent of assignee [due_today_reminder_sent_on]; uses [creator_due_today_reminder_sent_on].
 * Skips when status is completed/deleted (same as other due-today jobs).
 * Skips when create_by is the same as assignee_01 (creator is primary assignee — assignee due-today email suffices).
 */
async function runCreatorDueTodayReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (!isCalendarDueToday(todayYmd, taskRow.due_date)) continue;

    const lastCreator = taskRow.creator_due_today_reminder_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      supabase,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator due-today staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorDueTodayTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s task due today`),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun creator due-today task=${taskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('task')
      .update({ creator_due_today_reminder_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator due-today update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar due date = today: one email per sub-task to subtask.create_by.
 * Uses [subtask_creator_due_today_reminder_sent_on]. Skips completed/deleted.
 * Skips when create_by is the same as assignee_01.
 */
async function runCreatorDueTodaySubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    if (!isCalendarDueToday(todayYmd, row.due_date)) continue;

    const lastCreator = row.subtask_creator_due_today_reminder_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(supabase, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator due-today staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorDueTodaySubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName}'s sub-task due today`,
      ),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun subtask creator due-today subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('subtask')
      .update({ subtask_creator_due_today_reminder_sent_on: todayYmd })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator due-today update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > due_date. CreatorOverdueReminder → task.create_by (not when create_by = assignee_01).
 */
async function runCreatorOverdueTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;

    const lastCreator = taskRow.creator_overdue_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const taskId = String(taskRow.id || '').trim();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(
      supabase,
      creatorId,
    );
    if (staffErr) {
      summary.errors.push(`creator overdue staff lookup ${taskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for task ${taskId} (create_by=${creatorId}; try staff.id or staff.app_id)`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (taskRow.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `creator has no email (task ${taskId}, staff.id=${resolvedCreatorStaffId}; set staff.email or link app_users.email)`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (taskRow.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorOverdueTaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      taskName,
      taskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(`${picDisplayName}'s task overdue`),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun creator overdue task=${taskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('task')
      .update({ creator_overdue_reminder_last_sent_on: todayYmd })
      .eq('id', taskId);
    if (uErr) {
      summary.errors.push(`creator overdue update ${taskId}: ${uErr.message}`);
    } else {
      summary.tasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > due_date. AssigneeOverdueReminder → each non-empty assignee_01..10 (per slot / day).
 * Runs daily at 09:00 Asia/Hong_Kong (internal cron). Pending or Returned → send; Submitted → do not send.
 */
async function runAssigneeOverdueTaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    tasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: tasks, error: qErr } = await supabase
    .from('task')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = tasks || [];
  summary.scanned = list.length;

  for (const taskRow of list) {
    if (taskStatusBlocksUrgentReminder(taskRow.status)) continue;
    if (!isCalendarPastDue(todayYmd, taskRow.due_date)) continue;
    if (!submissionAllowsAssigneeOverdueReminder(taskRow.submission)) continue;

    const taskId = String(taskRow.id || '').trim();
    const taskName = String(taskRow.task_name || '').trim() || '(no title)';
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const dueYmd = formatTaskDueDateYYYYMMDD(taskRow.due_date);

    let anySlotThisTask = false;
    for (let slot = 1; slot <= 10; slot++) {
      const assigneeKey = `assignee_${String(slot).padStart(2, '0')}`;
      const sentCol = `${assigneeKey}_overdue_reminder_last_sent_on`;
      const staffId = (taskRow[assigneeKey] || '').toString().trim();
      if (!staffId) continue;

      const lastSent = taskRow[sentCol];
      const lastStr =
        lastSent == null || lastSent === ''
          ? null
          : String(lastSent).trim().slice(0, 10);
      if (lastStr === todayYmd) continue;

      if (!anySlotThisTask) {
        summary.eligible += 1;
        anySlotThisTask = true;
      }

      const { data: staffRow } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        summary.errors.push(`assignee overdue staff not found (task ${taskId}, ${assigneeKey})`);
        continue;
      }
      const to = await resolveStaffEmailForNotifications(supabase, staffRow);
      if (!to) {
        summary.errors.push(
          `assignee has no email (task ${taskId}, ${assigneeKey}, staff.id=${staffId})`,
        );
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;

      const { html, text } = buildAssigneeOverdueTaskReminderEmail(
        displayName,
        taskName,
        taskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: mailSubjectSingleLine('You have tasks overdue'),
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      else {
        summary.errors.push(
          `Mailgun assignee overdue task=${taskId} slot=${assigneeKey} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
        );
        continue;
      }

      const { error: uErr } = await supabase
        .from('task')
        .update({ [sentCol]: todayYmd })
        .eq('id', taskId);
      if (uErr) {
        summary.errors.push(`assignee overdue update ${taskId} ${sentCol}: ${uErr.message}`);
      } else {
        summary.tasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/**
 * HK calendar: today > subtask.due_date. Subtask_CreatorOverdueReminder → subtask.create_by (skip if = assignee_01).
 */
async function runCreatorOverdueSubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;

    const lastCreator = row.subtask_creator_overdue_reminder_last_sent_on;
    const lastCreatorStr =
      lastCreator == null || lastCreator === ''
        ? null
        : String(lastCreator).trim().slice(0, 10);
    if (lastCreatorStr === todayYmd) {
      continue;
    }

    const subtaskId = String(row.id || '').trim();
    const creatorId = (row.create_by || '').toString().trim();
    if (!creatorId) {
      continue;
    }

    const { data: staffRow, error: staffErr } = await fetchStaffRowForCreateBy(supabase, creatorId);
    if (staffErr) {
      summary.errors.push(`subtask creator overdue staff lookup ${subtaskId}: ${staffErr.message}`);
      continue;
    }
    if (!staffRow) {
      summary.errors.push(
        `creator staff not found for subtask ${subtaskId} (create_by=${creatorId})`,
      );
      continue;
    }
    const resolvedCreatorStaffId = String(staffRow.id || '').trim();
    const assignee01 = (row.assignee_01 || '').toString().trim();
    if (
      assignee01 &&
      resolvedCreatorStaffId.toLowerCase() === assignee01.toLowerCase()
    ) {
      continue;
    }

    summary.eligible += 1;
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);
    const to = await resolveStaffEmailForNotifications(supabase, staffRow);
    if (!to) {
      summary.errors.push(
        `subtask creator has no email (subtask ${subtaskId}, staff.id=${resolvedCreatorStaffId})`,
      );
      continue;
    }
    const recipientDisplayName =
      (staffRow.display_name || '').trim() ||
      (staffRow.name || '').trim() ||
      to;

    const picId = (row.pic || '').toString().trim();
    let picDisplayName = 'PIC';
    if (picId) {
      const { data: picStaff } = await supabase
        .from('staff')
        .select('display_name, name')
        .eq('id', picId)
        .maybeSingle();
      if (picStaff) {
        picDisplayName =
          (picStaff.display_name || '').trim() ||
          (picStaff.name || '').trim() ||
          picDisplayName;
      }
    }

    const { html, text } = buildCreatorOverdueSubtaskReminderEmail(
      recipientDisplayName,
      picDisplayName,
      subtaskName,
      subtaskUrl,
      dueYmd,
    );
    const r = await sendMailgun({
      to,
      subject: mailSubjectSingleLine(
        `${picDisplayName}'s sub-task overdue`,
      ),
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
    });
    summary.emailsAttempted += 1;
    if (r.ok) summary.emailsOk += 1;
    else {
      summary.errors.push(
        `Mailgun subtask creator overdue subtask=${subtaskId} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
      );
      continue;
    }

    const { error: uErr } = await supabase
      .from('subtask')
      .update({ subtask_creator_overdue_reminder_last_sent_on: todayYmd })
      .eq('id', subtaskId);
    if (uErr) {
      summary.errors.push(`subtask creator overdue update ${subtaskId}: ${uErr.message}`);
    } else {
      summary.subtasksUpdatedAfterSend += 1;
    }
  }

  return summary;
}

/**
 * HK calendar: today > subtask.due_date. Subtask_AssigneeOverdueReminder → each assignee slot (per slot / day).
 * Runs daily at 09:00 Asia/Hong_Kong (internal cron). Pending or Returned → send; Submitted → do not send.
 */
async function runAssigneeOverdueSubtaskReminderJob() {
  const todayYmd = hkTodayYyyyMmDd();
  const summary = {
    todayHk: todayYmd,
    scanned: 0,
    eligible: 0,
    emailsAttempted: 0,
    emailsOk: 0,
    subtasksUpdatedAfterSend: 0,
    errors: [],
  };
  if (!supabase) {
    summary.errors.push('Supabase not configured');
    return summary;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    summary.errors.push('Mailgun not configured');
    return summary;
  }

  const { data: subtasks, error: qErr } = await supabase
    .from('subtask')
    .select('*')
    .not('due_date', 'is', null);

  if (qErr) {
    summary.errors.push(qErr.message || String(qErr));
    return summary;
  }

  const list = subtasks || [];
  summary.scanned = list.length;
  const deletedParentIds = await fetchDeletedParentTaskIdSet(supabase);

  for (const row of list) {
    if (subtaskStatusBlocksUrgentReminder(row.status)) continue;
    const taskFk = String(row.task_id || '').trim();
    if (taskFk && deletedParentIds.has(taskFk)) continue;
    if (!isCalendarPastDue(todayYmd, row.due_date)) continue;
    if (!submissionAllowsAssigneeOverdueReminder(row.submission)) continue;

    const subtaskId = String(row.id || '').trim();
    const subtaskName = String(row.subtask_name || '').trim() || '(no title)';
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const dueYmd = formatTaskDueDateYYYYMMDD(row.due_date);

    let anySlotThisRow = false;
    for (let slot = 1; slot <= 10; slot++) {
      const assigneeKey = `assignee_${String(slot).padStart(2, '0')}`;
      const sentCol = `${assigneeKey}_overdue_reminder_last_sent_on`;
      const staffId = (row[assigneeKey] || '').toString().trim();
      if (!staffId) continue;

      const lastSent = row[sentCol];
      const lastStr =
        lastSent == null || lastSent === ''
          ? null
          : String(lastSent).trim().slice(0, 10);
      if (lastStr === todayYmd) continue;

      if (!anySlotThisRow) {
        summary.eligible += 1;
        anySlotThisRow = true;
      }

      const { data: staffRow } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffId)
        .maybeSingle();
      if (!staffRow) {
        summary.errors.push(`subtask assignee overdue staff not found (subtask ${subtaskId}, ${assigneeKey})`);
        continue;
      }
      const to = await resolveStaffEmailForNotifications(supabase, staffRow);
      if (!to) {
        summary.errors.push(
          `subtask assignee has no email (subtask ${subtaskId}, ${assigneeKey}, staff.id=${staffId})`,
        );
        continue;
      }
      const displayName =
        (staffRow.display_name || '').trim() ||
        (staffRow.name || '').trim() ||
        to;

      const { html, text } = buildAssigneeOverdueSubtaskReminderEmail(
        displayName,
        subtaskName,
        subtaskUrl,
        dueYmd,
      );
      const r = await sendMailgun({
        to,
        subject: mailSubjectSingleLine('You have sub-tasks overdue'),
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
      });
      summary.emailsAttempted += 1;
      if (r.ok) summary.emailsOk += 1;
      else {
        summary.errors.push(
          `Mailgun subtask assignee overdue subtask=${subtaskId} slot=${assigneeKey} to=${r.resolvedTo ?? to}: ${formatMailgunFailure(r)}`,
        );
        continue;
      }

      const { error: uErr } = await supabase
        .from('subtask')
        .update({ [sentCol]: todayYmd })
        .eq('id', subtaskId);
      if (uErr) {
        summary.errors.push(`subtask assignee overdue update ${subtaskId} ${sentCol}: ${uErr.message}`);
      } else {
        summary.subtasksUpdatedAfterSend += 1;
      }
    }
  }

  return summary;
}

/** Returns true if the request was rejected (response already sent). */
function cronUnauthorized(req, res) {
  if (!CRON_SECRET) {
    sendJson(req, res, 503, {
      error:
        'CRON_SECRET is not set on this server. In Railway → your service → Variables, add CRON_SECRET (any long random string), redeploy, then send the same value in the X-Cron-Secret header.',
    });
    return true;
  }
  if (!verifyCronSecret(req)) {
    sendJson(req, res, 401, {
      error:
        'X-Cron-Secret does not match CRON_SECRET on the server. Fix the header value or Railway Variables.',
    });
    return true;
  }
  return false;
}

async function handleCronUrgentTaskReminders(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    const urgent = await runUrgentTaskReminderJob();
    const assigneeUrgentSubtask = await runAssigneeUrgentSubtaskReminderJob();
    const creatorUrgent = await runCreatorUrgentTaskReminderJob();
    const creatorUrgentSubtask = await runCreatorUrgentSubtaskReminderJob();
    const dueToday = await runDueTodayTaskReminderJob();
    const assigneeDueTodaySubtask = await runAssigneeDueTodaySubtaskReminderJob();
    const creatorDueToday = await runCreatorDueTodayReminderJob();
    const creatorDueTodaySubtask = await runCreatorDueTodaySubtaskReminderJob();
    const creatorOverdue = await runCreatorOverdueTaskReminderJob();
    const assigneeOverdue = await runAssigneeOverdueTaskReminderJob();
    const creatorOverdueSubtask = await runCreatorOverdueSubtaskReminderJob();
    const assigneeOverdueSubtask = await runAssigneeOverdueSubtaskReminderJob();
    sendJson(req, res, 200, {
      ok: true,
      urgent,
      assigneeUrgentSubtask,
      creatorUrgent,
      creatorUrgentSubtask,
      dueToday,
      assigneeDueTodaySubtask,
      creatorDueToday,
      creatorDueTodaySubtask,
      creatorOverdue,
      assigneeOverdue,
      creatorOverdueSubtask,
      assigneeOverdueSubtask,
    });
  } catch (e) {
    console.error('handleCronUrgentTaskReminders:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** POST — only the due-today reminder job (HK calendar: today = due_date). Same CRON_SECRET as other cron routes. */
async function handleCronDueTodayOnly(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  if (cronUnauthorized(req, res)) return;
  try {
    const dueToday = await runDueTodayTaskReminderJob();
    const assigneeDueTodaySubtask = await runAssigneeDueTodaySubtaskReminderJob();
    const creatorDueToday = await runCreatorDueTodayReminderJob();
    const creatorDueTodaySubtask = await runCreatorDueTodaySubtaskReminderJob();
    sendJson(req, res, 200, {
      ok: true,
      dueToday,
      assigneeDueTodaySubtask,
      creatorDueToday,
      creatorDueTodaySubtask,
    });
  } catch (e) {
    console.error('handleCronDueTodayOnly:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — creator only; emails each assignee (assignee_01..10) with Mailgun.
 */
async function handleNotifyTaskAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorId = taskRow.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Task has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!creatorEmail || creatorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error: 'Only the task creator (staff email must match signed-in user) can send assignment emails',
      });
      return;
    }
    const staffDisplayName =
      (creatorStaff.display_name || '').trim() ||
      (creatorStaff.name || '').trim() ||
      creatorEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const dueLine = formatTaskDueDateYYYYMMDD(taskRow.due_date);
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;

    const assigneeIds = collectTaskAssigneeStaffIds(taskRow);

    const subject = "You've been assigned a task";
    const results = [];

    for (const staffUuid of assigneeIds) {
      const { data: s } = await supabase
        .from('staff')
        .select('email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const safeCreator = escapeHtml(staffDisplayName);
      const safeTitle = escapeHtml(taskName);
      const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
      const safeLanding = escapeHtml(landing);
      const html = `<p>${safeCreator} assigned you a task.</p><p><a href="${escapeHtml(taskUrl)}">${safeTitle}</a></p><p>Due Date: ${escapeHtml(dueLine)}</p><p><a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a></p>`;
      const text = `${staffDisplayName} assigned you a task.\n${taskName}\n${taskUrl}\nDue Date: ${dueLine}\nProject Tracker\n${landing}`;
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo: creatorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * Project assignment email (`handleNotifyProjectAssigned`): creator line + project link + Project Tracker; Aptos 16px.
 *
 * @param {{ creatorDisplayName: string, projectName: string, projectUrl: string }} p
 */
function buildProjectAssignedEmailHtml(p) {
  const safeCreator = escapeHtml(p.creatorDisplayName);
  const safeTitle = escapeHtml(p.projectName);
  const safeUrlAttr = escapeHtml(p.projectUrl);
  const safeLandingHref = escapeHtml(PROJECT_TRACKER_LANDING_URL);
  const bodyFont =
    "font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;";
  return `<div style="margin:0;${bodyFont}">${safeCreator} assigned you a project.<br><br>
<a href="${safeUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
}

function buildProjectAssignedEmailText(p) {
  return `${p.creatorDisplayName} assigned you a project.

${p.projectName}
${p.projectUrl}

Project Tracker
${PROJECT_TRACKER_LANDING_URL}`;
}

/**
 * POST { projectId } — creator only; emails each project assignee (assignee_01..10). Reply-To: creator email.
 * Duplicate assignee slots / create_by also an assignee: one message per distinct recipient email.
 */
async function handleNotifyProjectAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const projectId = (body.projectId || '').trim();
    if (!projectId) {
      sendJson(req, res, 400, { error: 'projectId required' });
      return;
    }
    const { data: projectRow, error: pErr } = await supabase
      .from('project')
      .select('*')
      .eq('id', projectId)
      .maybeSingle();
    if (pErr || !projectRow) {
      sendJson(req, res, 404, { error: 'Project not found' });
      return;
    }
    const creatorId = projectRow.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Project has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorMatchesSession = await sessionEmailBelongsToStaffRow(
      supabase,
      creatorStaff,
      sessionEmail,
    );
    if (!creatorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the project creator (signed-in email must match staff.email or linked app_users email) can send assignment emails',
      });
      return;
    }
    const creatorReplyTo = (
      (await resolveStaffEmailForNotifications(supabase, creatorStaff)) ||
      (creatorStaff.email || '').trim()
    ).trim();
    const staffDisplayName =
      (creatorStaff.display_name || '').trim() ||
      (creatorStaff.name || '').trim() ||
      creatorReplyTo ||
      sessionEmail ||
      'Colleague';
    const projectName = (projectRow.name || '').toString().trim() || '(no title)';
    const projectUrl = projectWebAppUrl(projectId);
    const assigneeUuids = collectTaskAssigneeStaffIds(projectRow);
    const subject = "You've been assigned a project";
    const results = [];
    const seenEmails = new Set();

    if (assigneeUuids.length === 0) {
      sendJson(req, res, 200, {
        ok: true,
        projectId,
        recipients: 0,
        results: [{ ok: true, skipped: 'no assignees on project' }],
      });
      return;
    }

    for (const staffUuid of assigneeUuids) {
      const { data: s } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      if (!s) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'assignee staff not found' });
        continue;
      }
      const to = (
        (await resolveStaffEmailForNotifications(supabase, s)) ||
        (s.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const toNorm = to.toLowerCase();
      if (seenEmails.has(toNorm)) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'duplicate recipient email (same inbox already notified)',
        });
        continue;
      }
      seenEmails.add(toNorm);
      const html = buildProjectAssignedEmailHtml({
        creatorDisplayName: staffDisplayName,
        projectName,
        projectUrl,
      });
      const text = buildProjectAssignedEmailText({
        creatorDisplayName: staffDisplayName,
        projectName,
        projectUrl,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo: creatorReplyTo || undefined,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      projectId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyProjectAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { projectId, changes } — signed-in email must match `project.update_by` (`staff` / `app_users`).
 * Emails each non-empty assignee slot only (deduped); skips updater when they are an assignee.
 */
async function handleNotifyProjectUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const projectId = (body.projectId || '').trim();
    if (!projectId) {
      sendJson(req, res, 400, { error: 'projectId required' });
      return;
    }
    const { data: projectRow, error: pErr } = await supabase
      .from('project')
      .select('*')
      .eq('id', projectId)
      .maybeSingle();
    if (pErr || !projectRow) {
      sendJson(req, res, 404, { error: 'Project not found' });
      return;
    }
    const updaterId = (projectRow.update_by || '').toString().trim();
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Project has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', updaterId)
      .maybeSingle();
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const updaterMatchesSession = await sessionEmailBelongsToStaffRow(
      supabase,
      updaterStaff,
      sessionEmail,
    );
    if (!updaterMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the project (signed-in email must match staff.email or linked app_users email for update_by) can send update emails',
      });
      return;
    }
    const updaterReplyTo = (
      (await resolveStaffEmailForNotifications(supabase, updaterStaff)) ||
      (updaterStaff.email || '').trim()
    ).trim();
    const updaterNameForBody =
      (updaterStaff.name || '').trim() ||
      (updaterStaff.display_name || '').trim() ||
      updaterReplyTo ||
      sessionEmail ||
      'Colleague';
    const projectName = (projectRow.name || '').toString().trim() || '(no title)';
    const projectTitleForSubject = mailSubjectSingleLine(projectName).replace(/"/g, '');
    const subject = `Project updated - ${projectTitleForSubject}`;
    const projectUrl = projectWebAppUrl(projectId);
    const updatedAtLine = formatUpdateDateTimeYmdHm(projectRow.update_date);

    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    let nCh = 0;
    for (const row of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!row || typeof row !== 'object') continue;
      const field = String(row.field || '').trim();
      const label = PROJECT_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = row.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(
        `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">${safeLbl} is updated – ${safeVal}</span>`,
      );
      changeLinesTextParts.push(`${label} is updated – ${value}`);
      nCh += 1;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br><br>');
    const changeLinesText = changeLinesTextParts.join('\n\n');

    if (changeLinesHtmlParts.length === 0) {
      sendJson(req, res, 200, {
        ok: true,
        skipped: true,
        projectId,
        message: 'No notifyable column changes in the request.',
        recipients: 0,
        results: [],
      });
      return;
    }

    const assigneeUuids = collectTaskAssigneeStaffIds(projectRow);
    const updaterNorm = updaterId.toLowerCase();
    const results = [];
    const replyTo = updaterReplyTo || sessionEmail || undefined;
    const seenEmails = new Set();

    for (const staffUuid of assigneeUuids) {
      if (String(staffUuid).trim().toLowerCase() === updaterNorm) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'updater is assignee; no self-email',
        });
        continue;
      }
      const { data: s } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      if (!s) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'assignee staff not found' });
        continue;
      }
      const to = (
        (await resolveStaffEmailForNotifications(supabase, s)) ||
        (s.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const toNorm = to.toLowerCase();
      if (seenEmails.has(toNorm)) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped: 'duplicate recipient email',
        });
        continue;
      }
      seenEmails.add(toNorm);
      const displayNameForHi =
        (s.display_name || '').trim() ||
        (s.name || '').trim() ||
        to;
      const html = buildSubtaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml: '',
        commentLineText: '',
        subtaskName: projectName,
        subtaskUrl: projectUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml: '',
        commentLineText: '',
        subtaskName: projectName,
        subtaskUrl: projectUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      projectId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyProjectUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — creator only; emails each subtask assignee (assignee_01..10) with Mailgun.
 * Creator receives mail only if they appear in assignee slots. Reply-To: creator email.
 */
async function handleNotifySubtaskAssigned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: tErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (tErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorId = row.create_by?.toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Sub-task has no create_by' });
      return;
    }
    const { data: creatorStaff, error: cErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', creatorId)
      .maybeSingle();
    if (cErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!creatorEmail || creatorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send assignment emails',
      });
      return;
    }
    const staffDisplayName =
      (creatorStaff.display_name || '').trim() ||
      (creatorStaff.name || '').trim() ||
      creatorEmail;
    const subtaskName =
      (row.subtask_name || '').toString().trim() || '(no title)';
    const dueLine = formatTaskDueDateYYYYMMDD(row.due_date);
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
    const assigneeUuids = collectSubtaskAssigneeStaffIds(row);
    const subject = "You've been assigned a sub-task";
    const results = [];
    const seenEmails = new Set();

    for (const staffUuid of assigneeUuids) {
      const { data: s } = await supabase
        .from('staff')
        .select('email, name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim().toLowerCase();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      if (seenEmails.has(to)) continue;
      seenEmails.add(to);
      const safeCreator = escapeHtml(staffDisplayName);
      const safeName = escapeHtml(subtaskName);
      const safeUrl = escapeHtml(subtaskUrl);
      const safeDue = escapeHtml(dueLine);
      const safeLanding = escapeHtml(landing);
      const html = `<div style="font-family: Aptos, Arial, Helvetica, sans-serif; font-size: 12pt;">${safeCreator} assigned you a sub-task.<br><br><a href="${safeUrl}"><strong><u>${safeName}</u></strong></a><br><br>Due Date: ${safeDue}<br><br><a href="${safeLanding}" style="color:#1565C0;">Project Tracker</a></div>`;
      const text = `${staffDisplayName} assigned you a sub-task.\n\n${subtaskName}\n${subtaskUrl}\n\nDue Date: ${dueLine}\n\nProject Tracker\n${landing}`;
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo: creatorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskAssigned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — comment author only; emails task creator (`create_by`) only when they are
 * not the comment author (no self-email when creator comments).
 */
async function handleNotifyTaskComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task comment email notifications are disabled.',
    });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await supabase
      .from('comment')
      .select('id, task_id, description, create_by')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Comment not found' });
      return;
    }
    const authorStaffId = (commentRow.create_by || '').toString().trim();
    if (!authorStaffId) {
      sendJson(req, res, 400, { error: 'Comment has no create_by' });
      return;
    }
    const { data: authorStaff, error: aErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', authorStaffId)
      .maybeSingle();
    if (aErr || !authorStaff) {
      sendJson(req, res, 400, { error: 'Comment author staff not found' });
      return;
    }
    const authorEmail = (authorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!authorEmail || authorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error: 'Only the comment author (staff email must match signed-in user) can send comment emails',
      });
      return;
    }
    const taskId = (commentRow.task_id || '').toString().trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'Comment has no task_id' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const authorNameForSubject =
      (authorStaff.display_name || '').trim() ||
      (authorStaff.name || '').trim() ||
      authorEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `${mailSubjectSingleLine(authorNameForSubject)} comments on task "${taskTitleForSubject}"`;
    const taskUrl = taskWebAppUrl(taskId);

    const authorNorm = authorStaffId.toLowerCase();
    const creatorId = (taskRow.create_by || '').toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Task has no create_by' });
      return;
    }
    if (authorNorm === creatorId.toLowerCase()) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'comment author is task creator; no self-email',
          },
        ],
      });
      return;
    }

    const { data: creatorStaff, error: crStaffErr } = await supabase
      .from('staff')
      .select('email, name, display_name')
      .eq('id', creatorId)
      .maybeSingle();
    if (crStaffErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Task creator staff not found' });
      return;
    }
    const to = (creatorStaff.email || '').trim();
    const results = [];
    if (!to) {
      results.push({
        staffId: creatorId,
        ok: false,
        skipped: 'no email on creator staff row',
      });
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results,
      });
      return;
    }

    const recipientDisplayName =
      (creatorStaff.display_name || '').trim() ||
      (creatorStaff.name || '').trim() ||
      to;
    const html = buildTaskCommentCreatorEmailHtml({
      recipientDisplayName,
      commentDescription: commentRow.description,
      taskName,
      taskUrl,
    });
    const text = buildTaskCommentCreatorEmailText({
      recipientDisplayName,
      commentDescription: commentRow.description,
      taskName,
      taskUrl,
    });

    const r = await sendMailgun({
      to,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: authorEmail,
    });
    results.push({
      to,
      ok: r.ok,
      mailgunId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — after a task comment is edited: Firebase email must match `staff.email` for
 * `comment.update_by`. Emails task `create_by` + assignee_01..10 (deduped), never the editor.
 */
async function handleNotifyTaskEditedComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task comment email notifications are disabled.',
    });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await supabase
      .from('comment')
      .select('id, task_id, description, update_by, update_date, create_date')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Comment not found' });
      return;
    }
    const editorStaffId = (commentRow.update_by || '').toString().trim();
    if (!editorStaffId) {
      sendJson(req, res, 400, { error: 'Comment has no update_by' });
      return;
    }
    const { data: editorStaff, error: edErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', editorStaffId)
      .maybeSingle();
    if (edErr || !editorStaff) {
      sendJson(req, res, 400, { error: 'Comment editor staff not found' });
      return;
    }
    const editorEmail = (editorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!editorEmail || editorEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the comment editor (staff email for update_by must match signed-in user) can send edit emails',
      });
      return;
    }
    const taskId = (commentRow.task_id || '').toString().trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'Comment has no task_id' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const editorNameForSubject =
      (editorStaff.display_name || '').trim() ||
      (editorStaff.name || '').trim() ||
      editorEmail;
    const subject = `${mailSubjectSingleLine(editorNameForSubject)} edited comments on task "${taskTitleForSubject}"`;
    const taskUrl = taskWebAppUrl(taskId);
    const updaterNameForBody =
      (editorStaff.name || '').trim() ||
      (editorStaff.display_name || '').trim() ||
      editorEmail;
    const updatedRaw =
      commentRow.update_date != null && String(commentRow.update_date).trim() !== ''
        ? commentRow.update_date
        : commentRow.create_date;
    const updatedAtLine = formatUpdateDateTimeYmdHm(updatedRaw);

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
    const editorNorm = editorStaffId.toLowerCase();
    recipientByNorm.delete(editorNorm);

    const results = [];
    if (recipientByNorm.size === 0) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        taskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'no recipients after excluding editor (creator/assignees)',
          },
        ],
      });
      return;
    }

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await supabase
        .from('staff')
        .select('email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientDisplayName =
        (s?.display_name || '').trim() ||
        (s?.name || '').trim() ||
        to;
      const html = buildTaskCommentEditedEmailHtml({
        recipientDisplayName,
        commentDescription: commentRow.description,
        taskName,
        taskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildTaskCommentEditedEmailText({
        recipientDisplayName,
        commentDescription: commentRow.description,
        taskName,
        taskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo: editorEmail,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      taskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskEditedComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — comment author only: Firebase email must match `staff.email` **or** any
 * `app_users.email` linked to `subtask_comment.create_by` → `staff.id`. Sends **one** Mailgun message
 * to **subtask.create_by** (resolved `staff` + `app_users` email) when the author is not the
 * sub-task creator (no self-email). Creator-only comments use `handleNotifySubtaskUpdated`.
 */
async function handleNotifySubtaskComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task/sub-task comment email notifications are disabled.',
    });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await supabase
      .from('subtask_comment')
      .select('id, subtask_id, description, create_by')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Sub-task comment not found' });
      return;
    }
    const authorStaffId = (commentRow.create_by || '').toString().trim();
    if (!authorStaffId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no create_by' });
      return;
    }
    const { data: authorStaff, error: aErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', authorStaffId)
      .maybeSingle();
    if (aErr || !authorStaff) {
      sendJson(req, res, 400, { error: 'Comment author staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const authorMatchesSession = await sessionEmailBelongsToStaffRow(
      supabase,
      authorStaff,
      sessionEmail,
    );
    if (!authorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the comment author (signed-in email must match staff.email or linked app_users email) can send comment emails',
      });
      return;
    }
    const authorReplyTo = (
      (await resolveStaffEmailForNotifications(supabase, authorStaff)) ||
      (authorStaff.email || '').trim()
    ).trim();
    const subtaskId = (commentRow.subtask_id || '').toString().trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no subtask_id' });
      return;
    }
    const { data: subtaskRow, error: tErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (tErr || !subtaskRow) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    /** Resolved from `subtask_comment.create_by` → staff (subject line). */
    const authorNameForSubject =
      (authorStaff.display_name || '').trim() ||
      (authorStaff.name || '').trim() ||
      sessionEmail ||
      authorReplyTo ||
      'Colleague';
    const subtaskName =
      (subtaskRow.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `${mailSubjectSingleLine(authorNameForSubject)} comments on sub-task "${subtaskTitleForSubject}"`;
    const subtaskRowId = (subtaskRow.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);

    const authorNorm = authorStaffId.toLowerCase();
    const creatorId = (subtaskRow.create_by || '').toString().trim();
    if (!creatorId) {
      sendJson(req, res, 400, { error: 'Sub-task has no create_by' });
      return;
    }
    if (authorNorm === creatorId.toLowerCase()) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'comment author is sub-task creator; no self-email',
          },
        ],
      });
      return;
    }

    const { data: creatorStaff, error: crStaffErr } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', creatorId)
      .maybeSingle();
    if (crStaffErr || !creatorStaff) {
      sendJson(req, res, 400, { error: 'Sub-task creator staff not found' });
      return;
    }
    const to = (
      (await resolveStaffEmailForNotifications(supabase, creatorStaff)) ||
      (creatorStaff.email || '').trim()
    ).trim();
    const results = [];
    if (!to) {
      results.push({
        staffId: creatorId,
        ok: false,
        skipped: 'no email on creator staff row',
      });
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results,
      });
      return;
    }

    const recipientDisplayName =
      (creatorStaff.display_name || '').trim() ||
      (creatorStaff.name || '').trim() ||
      to;
    const html = buildSubtaskCommentCreatorEmailHtml({
      recipientDisplayName,
      commentDescription: commentRow.description,
      subtaskName,
      subtaskUrl,
    });
    const text = buildSubtaskCommentCreatorEmailText({
      recipientDisplayName,
      commentDescription: commentRow.description,
      subtaskName,
      subtaskUrl,
    });

    const r = await sendMailgun({
      to,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: authorReplyTo || sessionEmail || undefined,
    });
    results.push({
      to,
      ok: r.ok,
      mailgunId: r.ok ? r.id : null,
      error: r.ok ? null : r.error,
      detail: r.ok ? null : r.detail,
    });

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { commentId } — after a sub-task comment is edited: signed-in email must match the editor’s
 * staff row (`subtask_comment.update_by`), via `staff.email` or linked `app_users`. Emails sub-task
 * `create_by` + assignee_01..10 (deduped), never the editor.
 */
async function handleNotifySubtaskEditedComment(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!TASK_COMMENT_EMAIL_ENABLED) {
    sendJson(req, res, 200, {
      ok: true,
      skipped: true,
      message: 'Task/sub-task comment email notifications are disabled.',
    });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const commentId = (body.commentId || '').trim();
    if (!commentId) {
      sendJson(req, res, 400, { error: 'commentId required' });
      return;
    }
    const { data: commentRow, error: cErr } = await supabase
      .from('subtask_comment')
      .select('id, subtask_id, description, update_by, update_date, create_date')
      .eq('id', commentId)
      .maybeSingle();
    if (cErr || !commentRow) {
      sendJson(req, res, 404, { error: 'Sub-task comment not found' });
      return;
    }
    const editorStaffId = (commentRow.update_by || '').toString().trim();
    if (!editorStaffId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no update_by' });
      return;
    }
    const { data: editorStaff, error: edErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', editorStaffId)
      .maybeSingle();
    if (edErr || !editorStaff) {
      sendJson(req, res, 400, { error: 'Comment editor staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const editorMatchesSession = await sessionEmailBelongsToStaffRow(
      supabase,
      editorStaff,
      sessionEmail,
    );
    if (!editorMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the comment editor (signed-in email must match staff.email or linked app_users email for update_by) can send edit emails',
      });
      return;
    }
    const editorReplyTo = (
      (await resolveStaffEmailForNotifications(supabase, editorStaff)) ||
      (editorStaff.email || '').trim()
    ).trim();
    const subtaskId = (commentRow.subtask_id || '').toString().trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'Sub-task comment has no subtask_id' });
      return;
    }
    const { data: subtaskRow, error: sErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !subtaskRow) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const subtaskName =
      (subtaskRow.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const editorNameForSubject =
      (editorStaff.display_name || '').trim() ||
      (editorStaff.name || '').trim() ||
      sessionEmail ||
      editorReplyTo ||
      'Colleague';
    const subject = `${mailSubjectSingleLine(editorNameForSubject)} edited comments on sub-task "${subtaskTitleForSubject}"`;
    const subtaskRowId = (subtaskRow.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);
    const updaterNameForBody =
      (editorStaff.name || '').trim() ||
      (editorStaff.display_name || '').trim() ||
      editorReplyTo ||
      sessionEmail ||
      'Colleague';
    const updatedRaw =
      commentRow.update_date != null && String(commentRow.update_date).trim() !== ''
        ? commentRow.update_date
        : commentRow.create_date;
    const updatedAtLine = formatUpdateDateTimeYmdHm(updatedRaw);

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(subtaskRow);
    const editorNorm = editorStaffId.toLowerCase();
    recipientByNorm.delete(editorNorm);

    const results = [];
    if (recipientByNorm.size === 0) {
      sendJson(req, res, 200, {
        ok: true,
        commentId,
        subtaskId,
        recipients: 0,
        results: [
          {
            ok: true,
            skipped: 'no recipients after excluding editor (creator/assignees)',
          },
        ],
      });
      return;
    }

    const replyTo = editorReplyTo || sessionEmail || undefined;

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (
        (await resolveStaffEmailForNotifications(supabase, s)) ||
        (s?.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const recipientDisplayName =
        (s?.display_name || '').trim() ||
        (s?.name || '').trim() ||
        to;
      const html = buildSubtaskCommentEditedEmailHtml({
        recipientDisplayName,
        commentDescription: commentRow.description,
        subtaskName,
        subtaskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskCommentEditedEmailText({
        recipientDisplayName,
        commentDescription: commentRow.description,
        subtaskName,
        subtaskUrl,
        updaterDisplayName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      commentId,
      subtaskId,
      recipients: results.filter((x) => x.ok && !x.skipped).length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskEditedComment:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — last updater only (session email = staff.email for task.update_by).
 * Emails each assignee (assignee_01..10) plus create_by, deduped; one Mailgun message per recipient.
 * If the updater is the task creator and the payload includes at least one allowed field change
 * (task detail columns), the creator is not emailed (no self-email for column edits).
 * Comment-only updates: assignee (not creator) commenting → notify create_by only; creator (not
 * assignee) commenting → notify assignees only. If that targeted set is empty, falls back to the
 * default full recipient list.
 */
async function handleNotifyTaskUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const taskCommentId = (body.taskCommentId || '').trim();
    let taskCommentRow = null;
    if (taskCommentId) {
      const { data: cRow, error: cErr } = await supabase
        .from('comment')
        .select('*')
        .eq('id', taskCommentId)
        .maybeSingle();
      if (cErr || !cRow || String(cRow.task_id || '').trim() !== taskId) {
        sendJson(req, res, 400, { error: 'taskCommentId does not match task' });
        return;
      }
      taskCommentRow = cRow;
    }
    let updaterId = (taskRow.update_by || '').toString().trim();
    if (!updaterId && taskCommentRow) {
      updaterId = (taskCommentRow.create_by || '').toString().trim();
    }
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Task has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', updaterId)
      .maybeSingle();
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const updaterEmail = (updaterStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    if (!updaterEmail || updaterEmail !== sessionEmail) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the task (staff email must match signed-in user) can send update emails',
      });
      return;
    }
    const updaterNameForBody =
      (updaterStaff.name || '').trim() || updaterEmail;
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `Task updated - ${taskTitleForSubject}`;
    const taskUrl = taskWebAppUrl(taskId);
    const taskRowHasUpdater = Boolean((taskRow.update_by || '').toString().trim());
    const updatedAtLine = taskCommentRow && !taskRowHasUpdater
      ? formatUpdateDateTimeYmdHm(taskCommentRow.create_date)
      : formatUpdateDateTimeYmdHm(taskRow.update_date);

    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    let nCh = 0;
    for (const row of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!row || typeof row !== 'object') continue;
      const field = String(row.field || '').trim();
      const label = TASK_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = row.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(
        `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">${safeLbl} is updated – ${safeVal}</span>`,
      );
      changeLinesTextParts.push(`${label} is updated – ${value}`);
      nCh += 1;
    }
    let commentLineHtml = '';
    let commentLineText = '';
    const rawComment =
      body.commentAddedText != null ? String(body.commentAddedText) : '';
    const commentTrim = rawComment.trim();
    if (commentTrim) {
      let c = commentTrim;
      if (c.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
        c = `${c.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
      }
      const safeC = escapeHtml(c);
      commentLineHtml = `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added – ${safeC}</span>`;
      commentLineText = `Comment is added – ${c}`;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br>');
    const changeLinesText = changeLinesTextParts.join('\n');

    const creatorId = (taskRow.create_by || '').toString().trim();
    const assigneeIdsForRouting = collectTaskAssigneeStaffIds(taskRow);
    /** @type {Map<string, string>} normalized staff id -> canonical id string */
    let recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);

    const updaterNorm = String(updaterId).trim().toLowerCase();
    const hasFieldChanges = changeLinesHtmlParts.length > 0;
    const hasComment = Boolean(commentTrim);
    const updaterInAssignees = assigneeIdsForRouting.some(
      (id) => String(id).trim().toLowerCase() === updaterNorm,
    );
    const updaterIsCreator =
      Boolean(creatorId) && updaterNorm === creatorId.toLowerCase();

    if (hasComment && !hasFieldChanges) {
      if (updaterInAssignees && !updaterIsCreator && creatorId) {
        recipientByNorm = new Map();
        recipientByNorm.set(creatorId.toLowerCase(), creatorId);
      } else if (updaterIsCreator && !updaterInAssignees) {
        recipientByNorm = new Map();
        for (const id of assigneeIdsForRouting) {
          const raw = String(id).trim();
          if (!raw) continue;
          const key = raw.toLowerCase();
          if (!recipientByNorm.has(key)) recipientByNorm.set(key, raw);
        }
      }
      if (recipientByNorm.size === 0) {
        recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(taskRow);
      }
    }

    const creatorNormKey = creatorId ? creatorId.toLowerCase() : '';
    const skipEnsureCreatorBecauseCreatorNotAssigneeComment =
      hasComment &&
      !hasFieldChanges &&
      updaterIsCreator &&
      !updaterInAssignees;
    if (
      hasComment &&
      !hasFieldChanges &&
      creatorId &&
      updaterNorm !== creatorNormKey &&
      !skipEnsureCreatorBecauseCreatorNotAssigneeComment
    ) {
      recipientByNorm.set(creatorNormKey, creatorId);
    }

    const omitSelfCreatorForFieldUpdates =
      changeLinesHtmlParts.length > 0 &&
      creatorId &&
      updaterNorm === creatorId.toLowerCase();

    const results = [];
    const replyTo = updaterEmail;

    for (const staffUuid of recipientByNorm.values()) {
      if (
        omitSelfCreatorForFieldUpdates &&
        String(staffUuid).trim().toLowerCase() === updaterNorm
      ) {
        results.push({
          staffId: staffUuid,
          ok: true,
          skipped:
            'task creator is updater (task detail columns changed); no self-email',
        });
        continue;
      }
      const { data: s } = await supabase
        .from('staff')
        .select('email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (s?.email || '').trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const displayNameForHi =
        (s.display_name || '').trim() ||
        (s.name || '').trim() ||
        to;
      const html = buildTaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        taskName,
        taskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildTaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        taskName,
        taskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      taskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifyTaskUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId, changes?, commentAddedText? } — only when `subtask.update_by` is the sub-task
 * creator (`create_by`) and session email matches that staff row. One Mailgun message per recipient:
 * assignee_01..10 (non-empty) plus `create_by`, deduped. Field lines: `{A} is updated – {new_value}`
 * for allowed keys; optional `commentAddedText`: `Sub-task comment is added – …` (creator comment).
 */
async function handleNotifySubtaskUpdated(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const subtaskCommentId = (body.subtaskCommentId || '').trim();
    let subtaskCommentRow = null;
    if (subtaskCommentId) {
      const { data: scRow, error: scErr } = await supabase
        .from('subtask_comment')
        .select('*')
        .eq('id', subtaskCommentId)
        .maybeSingle();
      if (scErr || !scRow || String(scRow.subtask_id || '').trim() !== subtaskId) {
        sendJson(req, res, 400, { error: 'subtaskCommentId does not match sub-task' });
        return;
      }
      subtaskCommentRow = scRow;
    }
    let updaterId = (row.update_by || '').toString().trim();
    if (!updaterId && subtaskCommentRow) {
      updaterId = (subtaskCommentRow.create_by || '').toString().trim();
    }
    if (!updaterId) {
      sendJson(req, res, 400, { error: 'Sub-task has no update_by' });
      return;
    }
    const { data: updaterStaff, error: uErr } = await supabase
      .from('staff')
      .select('id, name, email, display_name')
      .eq('id', updaterId)
      .maybeSingle();
    if (uErr || !updaterStaff) {
      sendJson(req, res, 400, { error: 'Updater staff not found' });
      return;
    }
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const updaterMatchesSession = await sessionEmailBelongsToStaffRow(
      supabase,
      updaterStaff,
      sessionEmail,
    );
    if (!updaterMatchesSession) {
      sendJson(req, res, 403, {
        error:
          'Only the user who updated the sub-task (signed-in email must match staff.email or linked app_users email) can send update emails',
      });
      return;
    }
    const updaterReplyTo = (
      (await resolveStaffEmailForNotifications(supabase, updaterStaff)) ||
      (updaterStaff.email || '').trim()
    ).trim();
    const updaterNameForBody =
      (updaterStaff.name || '').trim() ||
      updaterReplyTo ||
      sessionEmail ||
      'Colleague';
    const creatorId = (row.create_by || '').toString().trim();
    const updaterNorm = String(updaterId).trim().toLowerCase();
    const creatorNorm = creatorId ? creatorId.toLowerCase() : '';
    if (!creatorId || updaterNorm !== creatorNorm) {
      sendJson(req, res, 200, {
        ok: true,
        skipped: true,
        subtaskId,
        message:
          'Sub-task update notification emails are sent only when the sub-task creator saves changes or adds a comment.',
        recipients: 0,
        results: [],
      });
      return;
    }

    const subtaskTitle =
      (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskTitle).replace(/"/g, '');
    const subject = `Sub-task updated - ${subtaskTitleForSubject}`;
    const subtaskRowId = (row.id || subtaskId || '').toString().trim();
    const subtaskUrl = subtaskWebAppUrl(subtaskRowId);
    const rowHasUpdater = Boolean((row.update_by || '').toString().trim());
    const updatedAtLine = subtaskCommentRow && !rowHasUpdater
      ? formatUpdateDateTimeYmdHm(subtaskCommentRow.create_date)
      : formatUpdateDateTimeYmdHm(row.update_date);

    const dash = SUBTASK_COMMENT_ADDED_LINE_EN_DASH;
    const changeLinesHtmlParts = [];
    const changeLinesTextParts = [];
    const rawChanges = Array.isArray(body.changes) ? body.changes : [];
    let nCh = 0;
    for (const chRow of rawChanges) {
      if (nCh >= TASK_UPDATE_NOTIFY_MAX_CHANGES) break;
      if (!chRow || typeof chRow !== 'object') continue;
      const field = String(chRow.field || '').trim();
      const label = SUBTASK_UPDATE_NOTIFY_FIELD_LABELS[field];
      if (!label) continue;
      let value = chRow.value;
      if (value == null) value = '';
      value = String(value);
      if (value.length > TASK_UPDATE_NOTIFY_MAX_VALUE_LEN) {
        value = `${value.slice(0, TASK_UPDATE_NOTIFY_MAX_VALUE_LEN)}…`;
      }
      const safeVal = escapeHtml(value);
      const safeLbl = escapeHtml(label);
      changeLinesHtmlParts.push(`${safeLbl} is updated ${dash} ${safeVal}`);
      changeLinesTextParts.push(`${label} is updated ${dash} ${value}`);
      nCh += 1;
    }
    let commentLineHtml = '';
    let commentLineText = '';
    const rawSubComment =
      body.commentAddedText != null ? String(body.commentAddedText) : '';
    const commentPlain = subtaskCommentDescriptionPlainText(rawSubComment).trim();
    if (commentPlain) {
      let c = commentPlain;
      if (c.length > TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN) {
        c = `${c.slice(0, TASK_UPDATE_NOTIFY_MAX_COMMENT_LEN)}…`;
      }
      const safeC = escapeHtml(c);
      commentLineHtml = `<span style="color:#000000;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;">Comment is added ${dash} ${safeC}</span>`;
      commentLineText = `Comment is added ${dash} ${c}`;
    }
    const changeLinesHtml = changeLinesHtmlParts.join('<br><br>');
    const changeLinesText = changeLinesTextParts.join('\n\n');

    const hasFieldChanges = changeLinesHtmlParts.length > 0;
    const hasComment = Boolean(commentPlain);
    if (!hasFieldChanges && !hasComment) {
      sendJson(req, res, 200, {
        ok: true,
        skipped: true,
        subtaskId,
        message: 'No notifyable column changes or creator comment in the request.',
        recipients: 0,
        results: [],
      });
      return;
    }

    const recipientByNorm = buildTaskUpdatedDefaultRecipientStaffIds(row);
    const results = [];
    const replyTo =
      updaterReplyTo || sessionEmail || undefined;

    for (const staffUuid of recipientByNorm.values()) {
      const { data: s } = await supabase
        .from('staff')
        .select('id, email, name, display_name')
        .eq('id', staffUuid)
        .maybeSingle();
      const to = (
        (await resolveStaffEmailForNotifications(supabase, s)) ||
        (s?.email || '').trim()
      ).trim();
      if (!to) {
        results.push({ staffId: staffUuid, ok: false, skipped: 'no email on staff row' });
        continue;
      }
      const displayNameForHi =
        (s.display_name || '').trim() ||
        (s.name || '').trim() ||
        to;
      const html = buildSubtaskUpdatedAssigneeEmailHtml({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        subtaskName: subtaskTitle,
        subtaskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const text = buildSubtaskUpdatedAssigneeEmailText({
        recipientDisplayName: displayNameForHi,
        changeLinesHtml,
        changeLinesText,
        commentLineHtml,
        commentLineText,
        subtaskName: subtaskTitle,
        subtaskUrl,
        updaterName: updaterNameForBody,
        updatedAtLine,
      });
      const r = await sendMailgun({
        to,
        subject,
        text,
        html,
        from: MAILGUN_NOTIFICATION_FROM,
        replyTo,
      });
      results.push({
        to,
        ok: r.ok,
        mailgunId: r.ok ? r.id : null,
        error: r.ok ? null : r.error,
        detail: r.ok ? null : r.detail,
      });
    }

    sendJson(req, res, 200, {
      ok: true,
      subtaskId,
      recipients: results.length,
      results,
    });
  } catch (e) {
    console.error('handleNotifySubtaskUpdated:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/** Display name: display_name, else name, else email. */
function staffDisplayName(staffRow, fallbackEmail) {
  const dn = (staffRow?.display_name || '').trim();
  if (dn) return dn;
  const n = (staffRow?.name || '').trim();
  if (n) return n;
  return (fallbackEmail || '').trim() || 'Colleague';
}

function buildTaskWorkflowEmailShell(taskName, taskUrl, bodyLinesHtml, bodyLinesText) {
  const safeTitle = escapeHtml(taskName);
  const safeTaskUrlAttr = escapeHtml(taskUrl);
  const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
  const safeLandingHref = escapeHtml(landing);
  const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">${bodyLinesHtml}<br><br>
<a href="${safeTaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
  const text = `${bodyLinesText.join('\n\n')}

${taskName}
${taskUrl}

Project Tracker
${landing}`;
  return { html, text };
}

function buildSubtaskWorkflowEmailShell(subtaskName, subtaskUrl, bodyLinesHtml, bodyLinesText) {
  const safeTitle = escapeHtml(subtaskName);
  const safeSubtaskUrlAttr = escapeHtml(subtaskUrl);
  const landing = `${PROJECT_TRACKER_LANDING_URL}/`;
  const safeLandingHref = escapeHtml(landing);
  const html = `<div style="margin:0;font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;line-height:1.5;color:#000000;">${bodyLinesHtml}<br><br>
<a href="${safeSubtaskUrlAttr}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;font-weight:bold;text-decoration:underline;color:#1565C0;">${safeTitle}</a><br><br>
<a href="${safeLandingHref}" style="font-family:Aptos,'Segoe UI',Calibri,sans-serif;font-size:16px;color:#1565C0;">Project Tracker</a></div>`;
  const text = `${bodyLinesText.join('\n\n')}

${subtaskName}
${subtaskUrl}

Project Tracker
${landing}`;
  return { html, text };
}

/**
 * POST { taskId } — PIC only. To: create_by, Cc: pic. Submission for review.
 */
async function handleNotifyTaskSubmission(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const picId = (taskRow.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Task has no PIC' });
      return;
    }
    const { data: picStaff, error: pErr } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (pErr || !picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const picEmail = (picStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const picNotifyEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    const picAddr = (picNotifyEmail || picEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== picAddr) {
      sendJson(req, res, 403, {
        error: 'Only the task PIC (staff email must match signed-in user) can send submission emails',
      });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'Creator has no email' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `Submission for ${taskTitleForSubject}`;
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const creatorHi = staffDisplayName(creatorStaff, toEmail);
    const picLineName = staffDisplayName(picStaff, picAddr);
    const safeCreatorHi = escapeHtml(creatorHi);
    const safePicLine = escapeHtml(picLineName);
    const bodyLinesHtml = `Hi ${safeCreatorHi}.<br><br>${safePicLine} would like to seek you to review below task:`;
    const bodyLinesText = [
      `Hi ${creatorHi}.`,
      `${picLineName} would like to seek you to review below task:`,
    ];
    const { html, text } = buildTaskWorkflowEmailShell(taskName, taskUrl, bodyLinesHtml, bodyLinesText);
    const ccAddr = picNotifyEmail || picEmail;
    const r = await sendMailgun({
      to: toEmail,
      cc: ccAddr,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: picNotifyEmail || picEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, taskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifyTaskSubmission:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — create_by only. To: pic, Cc: create_by. Task accepted.
 */
async function handleNotifyTaskAccepted(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the task creator (staff email must match signed-in user) can send acceptance emails',
      });
      return;
    }
    const picId = (taskRow.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Task has no PIC' });
      return;
    }
    const { data: picStaff } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (!picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'PIC has no email' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `Submission for ${taskTitleForSubject}`;
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const picHi = staffDisplayName(picStaff, toEmail);
    const safePicHi = escapeHtml(picHi);
    const bodyLinesHtml = `Hi ${safePicHi}.<br><br>Your task has been accepted.`;
    const bodyLinesText = [`Hi ${picHi}.`, 'Your task has been accepted.'];
    const { html, text } = buildTaskWorkflowEmailShell(taskName, taskUrl, bodyLinesHtml, bodyLinesText);
    const r = await sendMailgun({
      to: toEmail,
      cc: creatorNotifyEmail || creatorEmail,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: creatorNotifyEmail || creatorEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, taskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifyTaskAccepted:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { taskId } — create_by only. To: pic, Cc: create_by. Task returned.
 */
async function handleNotifyTaskReturned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const taskId = (body.taskId || '').trim();
    if (!taskId) {
      sendJson(req, res, 400, { error: 'taskId required' });
      return;
    }
    const { data: taskRow, error: tErr } = await supabase
      .from('task')
      .select('*')
      .eq('id', taskId)
      .maybeSingle();
    if (tErr || !taskRow) {
      sendJson(req, res, 404, { error: 'Task not found' });
      return;
    }
    const creatorRaw = (taskRow.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the task creator (staff email must match signed-in user) can send return emails',
      });
      return;
    }
    const picId = (taskRow.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Task has no PIC' });
      return;
    }
    const { data: picStaff } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (!picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'PIC has no email' });
      return;
    }
    const taskName = (taskRow.task_name || '').toString().trim() || '(no title)';
    const taskTitleForSubject = mailSubjectSingleLine(taskName).replace(/"/g, '');
    const subject = `Submission for ${taskTitleForSubject}`;
    const taskUrl = `${PUBLIC_WEB_APP_URL}/?task=${encodeURIComponent(taskId)}`;
    const picHi = staffDisplayName(picStaff, toEmail);
    const safePicHi = escapeHtml(picHi);
    const bodyLinesHtml = `Hi ${safePicHi}.<br><br>Your task has been returned.`;
    const bodyLinesText = [`Hi ${picHi}.`, 'Your task has been returned.'];
    const { html, text } = buildTaskWorkflowEmailShell(taskName, taskUrl, bodyLinesHtml, bodyLinesText);
    const r = await sendMailgun({
      to: toEmail,
      cc: creatorNotifyEmail || creatorEmail,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: creatorNotifyEmail || creatorEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, taskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifyTaskReturned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — PIC only. To: create_by, Cc: pic. Submission for review.
 */
async function handleNotifySubtaskSubmission(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const picId = (row.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Sub-task has no PIC' });
      return;
    }
    const { data: picStaff, error: pErr } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (pErr || !picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const picEmail = (picStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const picNotifyEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    const picAddr = (picNotifyEmail || picEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== picAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task PIC (staff email must match signed-in user) can send submission emails',
      });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'Creator has no email' });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `Submission for ${subtaskTitleForSubject}`;
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const creatorHi = staffDisplayName(creatorStaff, toEmail);
    const picLineName = staffDisplayName(picStaff, picAddr);
    const safeCreatorHi = escapeHtml(creatorHi);
    const safePicLine = escapeHtml(picLineName);
    const bodyLinesHtml = `Hi ${safeCreatorHi}.<br><br>${safePicLine} would like to seek you to review below sub-task:`;
    const bodyLinesText = [
      `Hi ${creatorHi}.`,
      `${picLineName} would like to seek you to review below sub-task:`,
    ];
    const { html, text } = buildSubtaskWorkflowEmailShell(
      subtaskName,
      subtaskUrl,
      bodyLinesHtml,
      bodyLinesText,
    );
    const ccAddr = picNotifyEmail || picEmail;
    const r = await sendMailgun({
      to: toEmail,
      cc: ccAddr,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: picNotifyEmail || picEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, subtaskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifySubtaskSubmission:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — create_by only. To: pic, Cc: create_by. Sub-task accepted.
 */
async function handleNotifySubtaskAccepted(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send acceptance emails',
      });
      return;
    }
    const picId = (row.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Sub-task has no PIC' });
      return;
    }
    const { data: picStaff } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (!picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'PIC has no email' });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `Submission for ${subtaskTitleForSubject}`;
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const picHi = staffDisplayName(picStaff, toEmail);
    const safePicHi = escapeHtml(picHi);
    const bodyLinesHtml = `Hi ${safePicHi}.<br><br>Your sub-task has been accepted.`;
    const bodyLinesText = [`Hi ${picHi}.`, 'Your sub-task has been accepted.'];
    const { html, text } = buildSubtaskWorkflowEmailShell(
      subtaskName,
      subtaskUrl,
      bodyLinesHtml,
      bodyLinesText,
    );
    const r = await sendMailgun({
      to: toEmail,
      cc: creatorNotifyEmail || creatorEmail,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: creatorNotifyEmail || creatorEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, subtaskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifySubtaskAccepted:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

/**
 * POST { subtaskId } — create_by only. To: pic, Cc: create_by. Sub-task returned.
 */
async function handleNotifySubtaskReturned(req, res) {
  if (req.method !== 'POST') {
    sendJson(req, res, 405, { error: 'Method not allowed' });
    return;
  }
  const session = await verifyFirebaseToken(req.headers.authorization);
  if (!session) {
    sendJson(req, res, 401, { error: 'Unauthorized' });
    return;
  }
  if (!supabase) {
    sendJson(req, res, 503, { error: 'Supabase not configured' });
    return;
  }
  if (!MAILGUN_API_KEY || !MAILGUN_DOMAIN) {
    sendJson(req, res, 503, { error: 'Mailgun not configured' });
    return;
  }
  try {
    const body = await readBody(req);
    const subtaskId = (body.subtaskId || '').trim();
    if (!subtaskId) {
      sendJson(req, res, 400, { error: 'subtaskId required' });
      return;
    }
    const { data: row, error: sErr } = await supabase
      .from('subtask')
      .select('*')
      .eq('id', subtaskId)
      .maybeSingle();
    if (sErr || !row) {
      sendJson(req, res, 404, { error: 'Sub-task not found' });
      return;
    }
    const creatorRaw = (row.create_by || '').toString().trim();
    const { data: creatorStaff } = await fetchStaffRowForCreateBy(supabase, creatorRaw);
    if (!creatorStaff) {
      sendJson(req, res, 400, { error: 'Creator staff not found' });
      return;
    }
    const creatorEmail = (creatorStaff.email || '').trim().toLowerCase();
    const sessionEmail = (session.email || '').trim().toLowerCase();
    const creatorNotifyEmail = await resolveStaffEmailForNotifications(supabase, creatorStaff);
    const creatorAddr = (creatorNotifyEmail || creatorEmail).toLowerCase();
    if (!sessionEmail || sessionEmail !== creatorAddr) {
      sendJson(req, res, 403, {
        error:
          'Only the sub-task creator (staff email must match signed-in user) can send return emails',
      });
      return;
    }
    const picId = (row.pic || '').toString().trim();
    if (!picId) {
      sendJson(req, res, 400, { error: 'Sub-task has no PIC' });
      return;
    }
    const { data: picStaff } = await supabase
      .from('staff')
      .select('id, email, name, display_name')
      .eq('id', picId)
      .maybeSingle();
    if (!picStaff) {
      sendJson(req, res, 400, { error: 'PIC staff not found' });
      return;
    }
    const toEmail = await resolveStaffEmailForNotifications(supabase, picStaff);
    if (!toEmail) {
      sendJson(req, res, 400, { error: 'PIC has no email' });
      return;
    }
    const subtaskName = (row.subtask_name || '').toString().trim() || '(no title)';
    const subtaskTitleForSubject = mailSubjectSingleLine(subtaskName).replace(/"/g, '');
    const subject = `Submission for ${subtaskTitleForSubject}`;
    const subtaskUrl = subtaskWebAppUrl(subtaskId);
    const picHi = staffDisplayName(picStaff, toEmail);
    const safePicHi = escapeHtml(picHi);
    const bodyLinesHtml = `Hi ${safePicHi}.<br><br>Your sub-task has been returned.`;
    const bodyLinesText = [`Hi ${picHi}.`, 'Your sub-task has been returned.'];
    const { html, text } = buildSubtaskWorkflowEmailShell(
      subtaskName,
      subtaskUrl,
      bodyLinesHtml,
      bodyLinesText,
    );
    const r = await sendMailgun({
      to: toEmail,
      cc: creatorNotifyEmail || creatorEmail,
      subject,
      text,
      html,
      from: MAILGUN_NOTIFICATION_FROM,
      replyTo: creatorNotifyEmail || creatorEmail,
    });
    if (!r.ok) {
      sendJson(req, res, 502, { error: formatMailgunFailure(r) });
      return;
    }
    sendJson(req, res, 200, { ok: true, subtaskId, mailgunId: r.id || null });
  } catch (e) {
    console.error('handleNotifySubtaskReturned:', e);
    sendJson(req, res, 500, { error: e.message || String(e) });
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    applyCors(req, res, 204);
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
  if (path === '/api/admin/test-mailgun' && req.method === 'POST') {
    await handleAdminTestMailgun(req, res);
    return;
  }
  if (path === '/api/notify/task-assigned' && req.method === 'POST') {
    await handleNotifyTaskAssigned(req, res);
    return;
  }
  if (path === '/api/notify/subtask-assigned' && req.method === 'POST') {
    await handleNotifySubtaskAssigned(req, res);
    return;
  }
  if (path === '/api/notify/project-assigned' && req.method === 'POST') {
    await handleNotifyProjectAssigned(req, res);
    return;
  }
  if (path === '/api/notify/project-updated' && req.method === 'POST') {
    await handleNotifyProjectUpdated(req, res);
    return;
  }
  if (path === '/api/notify/task-comment' && req.method === 'POST') {
    await handleNotifyTaskComment(req, res);
    return;
  }
  if (path === '/api/notify/task-comment-edited' && req.method === 'POST') {
    await handleNotifyTaskEditedComment(req, res);
    return;
  }
  if (path === '/api/notify/subtask-comment' && req.method === 'POST') {
    await handleNotifySubtaskComment(req, res);
    return;
  }
  if (path === '/api/notify/subtask-comment-edited' && req.method === 'POST') {
    await handleNotifySubtaskEditedComment(req, res);
    return;
  }
  if (path === '/api/notify/task-updated' && req.method === 'POST') {
    await handleNotifyTaskUpdated(req, res);
    return;
  }
  if (path === '/api/notify/subtask-updated' && req.method === 'POST') {
    await handleNotifySubtaskUpdated(req, res);
    return;
  }
  if (path === '/api/notify/task-submission' && req.method === 'POST') {
    await handleNotifyTaskSubmission(req, res);
    return;
  }
  if (path === '/api/notify/task-accepted' && req.method === 'POST') {
    await handleNotifyTaskAccepted(req, res);
    return;
  }
  if (path === '/api/notify/task-returned' && req.method === 'POST') {
    await handleNotifyTaskReturned(req, res);
    return;
  }
  if (path === '/api/notify/subtask-submission' && req.method === 'POST') {
    await handleNotifySubtaskSubmission(req, res);
    return;
  }
  if (path === '/api/notify/subtask-accepted' && req.method === 'POST') {
    await handleNotifySubtaskAccepted(req, res);
    return;
  }
  if (path === '/api/notify/subtask-returned' && req.method === 'POST') {
    await handleNotifySubtaskReturned(req, res);
    return;
  }
  if (path === '/api/cron/urgent-task-reminders' && req.method === 'POST') {
    await handleCronUrgentTaskReminders(req, res);
    return;
  }
  if (path === '/api/cron/due-today-reminders' && req.method === 'POST') {
    await handleCronDueTodayOnly(req, res);
    return;
  }
  if (path === '/api/attachment/open-session' && req.method === 'POST') {
    await handleAttachmentOpenSession(req, res);
    return;
  }
  if (path === '/api/attachment/stream' && req.method === 'GET') {
    await handleAttachmentStream(req, res);
    return;
  }
  if (path === '/health' || path === '/') {
    await handleHealth(req, res);
    return;
  }

  sendJson(req, res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
  console.log(
    `Firebase Admin: ${firebaseAdmin ? 'ok' : 'missing FIREBASE_SERVICE_ACCOUNT_JSON'}`,
  );
  console.log(
    `Supabase: ${supabase ? 'ok' : 'missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY'}`,
  );
  console.log(
    `Attachment stream signing: ${getAttachmentStreamSigningSecret() ? 'ok (ATTACHMENT_STREAM_SIGNING_SECRET or CRON_SECRET)' : 'MISSING — set ATTACHMENT_STREAM_SIGNING_SECRET or CRON_SECRET for /api/attachment/*'}`,
  );
  console.log(
    `Mailgun: ${MAILGUN_API_KEY && MAILGUN_DOMAIN ? 'ok' : 'optional (MAILGUN_API_KEY, MAILGUN_DOMAIN)'}`,
  );
  if (process.env.DISABLE_INTERNAL_URGENT_CRON !== 'true') {
    cron.schedule(
      '0 9 * * *',
      () => {
        runUrgentTaskReminderJob()
          .then(() => runAssigneeUrgentSubtaskReminderJob())
          .then(() => runCreatorUrgentTaskReminderJob())
          .then(() => runCreatorUrgentSubtaskReminderJob())
          .then(() => runDueTodayTaskReminderJob())
          .then(() => runAssigneeDueTodaySubtaskReminderJob())
          .then(() => runCreatorDueTodayReminderJob())
          .then(() => runCreatorDueTodaySubtaskReminderJob())
          .then(() => runCreatorOverdueTaskReminderJob())
          .then(() => runAssigneeOverdueTaskReminderJob())
          .then(() => runCreatorOverdueSubtaskReminderJob())
          .then(() => runAssigneeOverdueSubtaskReminderJob())
          .catch((e) => console.error('daily task-reminder cron:', e));
      },
      { timezone: 'Asia/Hong_Kong' },
    );
    console.log(
      'Task reminders: urgent (80%) + due-today + overdue (task/sub-task creators + assignees) daily at 09:00 Asia/Hong_Kong (DISABLE_INTERNAL_URGENT_CRON=true to turn off)',
    );
  }
});
