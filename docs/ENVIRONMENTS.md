# Testing vs production

Single Firebase project (**DAAO** / `daao-a20c6`) hosts **two** sites. Supabase and Railway use **separate** projects for test vs prod.

**GitHub:** two repos (test vs prod) — see **`GITHUB_SETUP.md`** for branch rules, Railway connection, and optional CI secrets.

## Overview

| Layer | Testing | Production |
|--------|---------|------------|
| **Firebase project** | DAAO (`daao-a20c6`) | Same |
| **Firebase Hosting site ID** | `project-tracker-test` | `projecttrackerdaao` |
| **Default Firebase URLs** | https://project-tracker-test.web.app/ · https://project-tracker-test.firebaseapp.com/ | https://projecttrackerdaao.web.app/ |
| **Custom domain (HKU)** | https://projecttrackertest.hku-ia.ai/ (optional) | https://projecttracker.hku-ia.ai/ (optional) |
| **Supabase project** | **DAAO Tests** — `kxrimbbeyirmcjtszsvm` — https://kxrimbbeyirmcjtszsvm.supabase.co | **DAAO Apps** — `cjeyowmqhluiilrhkvmj` — https://cjeyowmqhluiilrhkvmj.supabase.co |
| **Railway** | Calvin's Test Space — `project-tracker-test-production.up.railway.app` | DAAO Apps — `project-tracker-production-1588.up.railway.app` |

> **Note:** Production Supabase URL must use **`supabase.co`** (not `supbase.co`).

## Flutter web (`lib/config`)

- **`DEPLOY_ENV`** (compile-time):
  - Default: **`testing`** → DAAO Tests Supabase + test Railway API.
  - **`production`** → DAAO Apps Supabase + production Railway API.
- **Optional overrides:**
  - `SUPABASE_ANON_KEY` — anon public key (overrides values in `supabase_config.dart`).
  - `API_BASE_URL` — backend base URL (no trailing slash).

### Commands

**Deploy to the test site** (DAAO Tests + test Railway):

```powershell
flutter build web --release --no-wasm-dry-run
firebase deploy --only hosting:testing
```

**Deploy to the production site** (DAAO Apps + production Railway):

```powershell
flutter build web --release --no-wasm-dry-run --dart-define=DEPLOY_ENV=production
firebase deploy --only hosting:production
```

### First-time: DAAO Tests Supabase anon key

With `DEPLOY_ENV=testing` (default), set the **anon public** key for project **DAAO Tests**:

1. Supabase Dashboard → **DAAO Tests** → Project Settings → API → **anon public**, **or**
2. Build with `--dart-define=SUPABASE_ANON_KEY=eyJ...`, **or**
3. Paste into `_testingAnonKey` in `lib/config/supabase_config.dart` (avoid committing secrets if the repo is shared).

Until the testing anon key is set, `SupabaseConfig.isConfigured` is false and the app runs without Supabase sync.

## Firebase Hosting targets

Targets are defined in **`.firebaserc`** (maps to Hosting site IDs). If deploy fails with “target not found”, link the site once:

```powershell
firebase target:apply hosting testing project-tracker-test
firebase target:apply hosting production projecttrackerdaao
```

Use **site ID only** (no `projectId:` prefix).

### Custom domains (`*.hku-ia.ai`)

Custom domains are **not** set in the Flutter repo. Configure them in Firebase and DNS:

1. [Firebase Console](https://console.firebase.google.com/) → **daao-a20c6** → **Hosting**.
2. Click the **testing** site (`project-tracker-test`) → **Domains** → **Add custom domain** → enter **`projecttrackertest.hku-ia.ai`** → follow the wizard (TXT verification, then **A/CNAME** records Firebase shows).
3. **Production** site (`projecttrackerdaao`) → **Add custom domain** → **`projecttracker.hku-ia.ai`** → same process.
4. **HTTPS** is provisioned automatically after DNS propagates (can take up to 24–48 hours).

**Firebase Authentication → Authorized domains** (Settings → Authorized domains): add:

- `projecttrackertest.hku-ia.ai`
- `projecttracker.hku-ia.ai`

(Also keep `localhost` and the default `*.firebaseapp.com` / `*.web.app` entries as needed.)

If **`projecttrackerdaao`** does not exist yet: Hosting → **Add another site** → site ID **`projecttrackerdaao`**, then add domains as above.

## Railway (backend)

Each Railway project has its own variables. Point each deployment to the matching Supabase:

| Variable | Testing Railway | Production Railway |
|----------|-----------------|-------------------|
| `SUPABASE_URL` | `https://kxrimbbeyirmcjtszsvm.supabase.co` | `https://cjeyowmqhluiilrhkvmj.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role from **DAAO Tests** | service_role from **DAAO Apps** |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Same Firebase project `daao-a20c6` (one JSON works for both) | Same |

Use the **service_role** key from the **same** Supabase project as `SUPABASE_URL`.

**CORS (Flutter web → Railway):** The Node server in `backend/server.js` sends CORS headers for Firebase Hosting URLs (including **`https://project-tracker-test.web.app`**). After changing CORS or adding a new web origin, **redeploy** the Railway service. Optional env **`CORS_ORIGINS`** adds extra comma-separated origins (see `backend/README.md`).

## Railway project IDs (dashboard reference)

| Environment | Railway project name | Project ID |
|-------------|----------------------|------------|
| Testing | Calvin's Test Space | `7a6f3d2b-ce23-45f8-a544-b182391c8221` |
| Production | DAAO Apps | `d05a96f2-32c7-4c24-9188-2aac097c752a` |

## Supabase schema

Apply the same migrations to **both** Supabase projects if both should behave the same (see `supabase/migrations/` and `supabase/README.md`).
