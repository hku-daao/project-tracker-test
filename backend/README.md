# Backend

Node.js backend for the Project Tracker (DAAO Apps). Serves `/api/me` and `/api/assignable-staff` for RBAC (role-based assignee list).

## 1. Install dependencies

```bash
cd backend
npm install
```

## 2. Environment variables (required for RBAC)

Copy `.env.example` to `.env` and set these three variables:

| Variable | Where to get it |
|----------|-----------------|
| **SUPABASE_URL** | [Supabase](https://supabase.com/dashboard) → your project → **Project Settings** (gear) → **API** → **Project URL** |
| **SUPABASE_SERVICE_ROLE_KEY** | Same page → **Project API keys** → **service_role** (secret). Use this, not the anon key. |
| **FIREBASE_SERVICE_ACCOUNT_JSON** | [Firebase Console](https://console.firebase.google.com/) → your project (e.g. daao-a20c6) → **Project settings** (gear) → **Service accounts** → **Generate new private key** → download JSON. Paste the **entire JSON as one line** (no line breaks) as the value. |
| **CORS_ORIGINS** (optional) | Comma-separated extra **https** origins for the Flutter web app (e.g. a custom domain). Built-in defaults already include `https://project-tracker-test.web.app`, production `*.web.app` URLs, and HKU domains. Set this if you host the web app on another hostname. |
| **MAILGUN_API_KEY** (optional) | Mailgun **Private API key** (`key-…`). |
| **MAILGUN_DOMAIN** (optional) | Sending domain in Mailgun (e.g. sandbox `sandbox….mailgun.org`). |
| **MAILGUN_BASE_URL** (optional) | Default `https://api.mailgun.net` (US). Use `https://api.eu.mailgun.net` for EU domains. |
| **MAILGUN_FROM** (optional) | Default **From** when Mailgun is called without an override (e.g. admin test email). If omitted, the server uses `postmaster@<MAILGUN_DOMAIN>`. |
| **MAILGUN_NOTIFICATION_FROM** (optional) | Verified **From** for **task-assignment** emails (`POST /api/notify/task-assigned`). Defaults to `no-reply@sandbox1d79a2f6002c44b28ab0f0ec99a11179.mailgun.org` for the sandbox domain; set this when you use a production Mailgun domain. **Reply-To** is still the creator’s `staff.email`. |
| **PUBLIC_WEB_APP_URL** (optional) | Public HTTPS origin for **task links in emails** (no trailing slash), e.g. `https://projecttracker.hku-ia.ai` (production) or `https://project-tracker-test.web.app` (testing). Default: `https://projecttracker.hku-ia.ai`. |
| **CRON_SECRET** (optional) | Shared secret for cron HTTP routes (**`POST /api/cron/urgent-task-reminders`**, **`POST /api/cron/due-today-reminders`**) — header `X-Cron-Secret` or `Authorization: Bearer …`. Required for those routes to return 200. |
| **DISABLE_INTERNAL_URGENT_CRON** (optional) | Set to `true` to disable the in-process **daily 09:00 Asia/Hong_Kong** run that sends **80% window** urgent task emails. |

Apply Supabase migrations **`028`**–**`030`** (`urgent_reminder_sent`, `urgent_reminder_last_sent_on`, `due_today_reminder_sent_on`). **Urgent (80%)** emails run only on HK calendar days **before** the due date; **due-today** emails run when HK **today** equals `due_date`. **`POST /api/cron/urgent-task-reminders`** returns JSON `{ ok, urgent, dueToday }`. After the due date (HK), past-due cleanup clears the reminder columns.

Assignment emails (`POST /api/notify/task-assigned`) require the signed-in user’s Firebase **email** to match **`staff.email`** for `task.create_by`, or the API returns 403.

### Mailgun test (admin only)

After the variables above are set, redeploy Railway. `GET /health` includes `mailgunConfigured: true` when the key and domain are non-empty.

**Send one test email** (must be signed in as the user whose email equals **`ADMIN_EMAIL`** on Railway):

`POST /api/admin/test-mailgun` with header `Authorization: Bearer <Firebase ID token>` and JSON body `{ "to": "recipient@example.com" }`.

- **Sandbox domain:** In [Mailgun](https://app.mailgun.com/) → *Sending* → *Domains* → your sandbox → **Authorized recipients** — add the inbox you use in `"to"`. Sandbox cannot send to arbitrary addresses.

### Get Firebase service account JSON (step by step)

1. Open [Firebase Console](https://console.firebase.google.com/) and select your project (**daao-a20c6**).
2. Click the **gear** next to “Project Overview” → **Project settings**.
3. Open the **Service accounts** tab.
4. Click **Generate new private key** → confirm. A JSON file downloads.
5. Open the file in a text editor. Copy the whole content (one object `{ "type": "service_account", ... }`).
6. For **Railway**: paste that JSON as a **single line** (replace any line breaks with nothing or a space). Set the env var `FIREBASE_SERVICE_ACCOUNT_JSON` to that string.
7. For **local `.env`**: you can either paste the one-line JSON after `FIREBASE_SERVICE_ACCOUNT_JSON=` or use a tool to escape quotes; some hosts allow multi-line if you wrap in `"..."`.

Example `.env` (fake values):

```env
SUPABASE_URL=https://cjeyowmqhluiilrhkvmj.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOi...
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"daao-a20c6","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","client_id":"...","auth_uri":"...","token_uri":"...","auth_provider_x509_cert_url":"...","client_x509_cert_url":"..."}
```

**Important:** Do not commit `.env`. It is in `.gitignore`.

## 3. Run locally

Create a `.env` file in the `backend` folder with the three variables (see section 2). The server loads `.env` automatically via `dotenv`. Then:

```bash
npm install
node server.js
```

Server runs at `http://localhost:3000` (or `PORT` from env). Test: `curl http://localhost:3000/` and `curl -H "Authorization: Bearer YOUR_FIREBASE_ID_TOKEN" http://localhost:3000/api/me`.

## 4. Railway deployment

You may have **two** Railway backends (testing vs production). The Flutter app’s `ApiConfig.baseUrl` follows **`DEPLOY_ENV`** — see **`docs/ENVIRONMENTS.md`** in the repo root.

| Environment | Example URL |
|-------------|-------------|
| Testing | `https://project-tracker-test-production.up.railway.app` |
| Production | `https://project-tracker-production-1588.up.railway.app` |

On **each** Railway service, set **`SUPABASE_URL`** and **`SUPABASE_SERVICE_ROLE_KEY`** from the **matching** Supabase project (DAAO Tests vs DAAO Apps). **`FIREBASE_SERVICE_ACCOUNT_JSON`** can be the same for both (Firebase project `daao-a20c6`).

### Set environment variables on Railway

1. Go to [Railway Dashboard](https://railway.app/dashboard) and open the backend service for **testing** or **production**.
2. Click the **backend service** (the one that runs `node server.js`).
3. Open the **Variables** tab (or **Settings** → **Variables**).
4. Add three variables:
   - **SUPABASE_URL** = your Supabase project URL (e.g. `https://xxxxx.supabase.co`)
   - **SUPABASE_SERVICE_ROLE_KEY** = the **service_role** key from Supabase (long JWT)
   - **FIREBASE_SERVICE_ACCOUNT_JSON** = the full Firebase service account JSON as **one line** (paste the entire JSON; remove newlines so it’s a single line)
5. Save. Railway will redeploy automatically when you add/change variables (or trigger a redeploy from the **Deployments** tab).

### Redeploy after code changes

- **Option A:** Push your code to GitHub (if the backend is connected to a repo). Railway will redeploy on push.
- **Option B:** In Railway, open **Deployments** → click **Redeploy** on the latest deployment.

After redeploy, the live backend will use the new env vars and the Flutter web app will get role and assignable staff from `GET /api/me`.
