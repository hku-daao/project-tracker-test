# GitHub setup — testing vs production

**Repos**

| | Link |
|---|------|
| **Testing** | https://github.com/hku-daao/project-tracker-test |
| **Production** | https://github.com/hku-daao/project-tracker |

---

## Part A — Read this first (what GitHub is for)

| Task | Where you do it |
|------|-----------------|
| Firebase “authorized domains” (so login works on your URLs) | **Firebase Console** — **not** GitHub |
| Supabase keys, Railway env vars | **Supabase / Railway dashboards** — **not** GitHub (unless you add automated deploy later) |
| Store code, control who can merge to production, connect Railway to the right repo | **GitHub** |

So: **GitHub = code + permissions + (optional) automation.** You do **not** paste Firebase domains into GitHub.

---

## Part B — Minimum steps (do these on GitHub)

### Step 1 — Decide which repo is “production”

Use this rule (simplest for a team):

- **`hku-daao/project-tracker`** = **production** code (the real app users will use).
- **`hku-daao/project-tracker-test`** = **testing / staging** (try changes here first).

Write one short paragraph in each repo’s **README** (you can copy this and edit):

**In `project-tracker` README:**

```text
This repository is the PRODUCTION source code for the Project Tracker.
The `main` branch should always be deployable to production.
```

**In `project-tracker-test` README:**

```text
This repository is for TESTING / STAGING.
We merge or copy stable changes into `hku-daao/project-tracker` when ready for production.
```

*(How to edit README: open the repo on GitHub → if README exists, click the pencil “Edit”; if not, click “Add a README”.)*

---

### Step 2 — Add collaborators (if others need access)

For **each** repo (`project-tracker` and `project-tracker-test`):

1. Open the repo on GitHub.
2. Click **Settings** (top menu of the repo).
3. In the left sidebar, click **Collaborators** (under “Access” or “Collaborators and teams”).
4. Click **Add people** → enter GitHub username or email → choose role (**Write** is enough for developers who push code; **Admin** only for people who change settings).

Repeat for both repos so the **same people** (or the right subset) have access.

---

### Step 3 — Protect the production `main` branch (strongly recommended)

Do this only on **`hku-daao/project-tracker`** (production):

1. Open https://github.com/hku-daao/project-tracker  
2. Click **Settings**.  
3. Left sidebar: **Branches** (under “Code and automation”).  
4. Under **Branch protection rules**, click **Add rule** (or **Add branch ruleset** — GitHub sometimes shows two UIs; the idea is the same).  
5. **Branch name pattern:** type `main` (if your default branch is `master`, use `master` instead).  
6. Turn **on** at least:
   - **Require a pull request before merging**  
     - Optionally: **Require approvals** → set to `1` (someone else must approve).  
7. Click **Create** / **Save**.

Result: nobody should push straight to `main` on production without a PR (you can still allow admins to bypass in advanced settings if your org allows it).

**Optional:** On **`project-tracker-test`**, you can skip strict rules so people can push to `main` quickly for testing.

---

### Step 4 — (When you use Railway + GitHub) Connect the correct repo to each Railway project

This is still “something you do **involving** GitHub,” but part of the flow happens in **Railway**.

**Goal:**

- **Testing** Railway backend → deploys from **`project-tracker-test`** (e.g. branch `main`).
- **Production** Railway backend → deploys from **`project-tracker`** (branch `main`).

**In Railway (not inside GitHub’s settings, but GitHub will ask you to authorize):**

1. Open your **testing** Railway project → your **backend** service → **Settings** (or **Connect** / **Source**).  
2. Connect **GitHub** → choose organization **`hku-daao`** → repo **`project-tracker-test`** → branch **`main`**.  
3. GitHub may show a popup: **Authorize Railway** — click **Authorize** (or **Install**) so Railway can read that repo and deploy on push.

Repeat for **production** Railway project → repo **`project-tracker`** → branch **`main`** → authorize if asked.

**On GitHub**, after you do this, you can verify:

1. Open **your profile** (top right) → **Settings** → **Applications** → **Authorized OAuth Apps** or **Installed GitHub Apps**.  
2. You should see **Railway** with access to the repos you selected.

You do **not** need to add Railway secrets manually in GitHub for normal “deploy from repo” — Railway uses this app connection.

---

## Part C — Optional (skip until you need them)

### Optional 1 — GitHub Environments (`testing` / `production`)

**When:** You plan to use **GitHub Actions** to deploy (build Flutter + `firebase deploy` automatically).

**Steps:**

1. Open **one** repo (usually production): **Settings** → **Environments** (left sidebar).  
2. **New environment** → name: `testing` → **Configure environment**.  
3. Repeat → name: `production` → you can add **Required reviewers** for production.  
4. Later, workflows put **secrets** under each environment (different Firebase keys per env).

**If you deploy only from your PC** with `firebase deploy`, you can **skip** Environments for now.

---

### Optional 2 — Repository secrets (for CI only)

**When:** You add a workflow (`.github/workflows/...`) that runs `firebase deploy` or needs API keys.

**Steps:**

1. Repo **Settings** → **Secrets and variables** → **Actions**.  
2. **New repository secret** → name e.g. `FIREBASE_SERVICE_ACCOUNT` → paste value (JSON one line).  

**Do not** add secrets until you actually have a workflow file that uses them.

---

### Optional 3 — Dependabot

1. Repo **Settings** → **Code security and analysis**.  
2. Enable **Dependabot alerts** (and optionally **Dependabot security updates**).

---

## Part D — What you do NOT need on GitHub (common confusion)

| Question | Answer |
|----------|--------|
| Do I add Firebase test/prod URLs in GitHub? | **No** — add domains in **Firebase Console → Authentication → Authorized domains**. |
| Do I store Supabase keys in GitHub? | **Only** if you automate builds in Actions and inject keys via secrets. Otherwise keys stay in your app config / local / CI vault, not required in GitHub. |
| Must I create two “Environments” before Railway works? | **No** — Environments are for Actions/deploy rules. Railway only needs the **GitHub app connection** (Part B Step 4). |

---

## Part E — Checklist (copy and tick)

**Minimum**

- [ ] README on **`project-tracker`** says it is production.  
- [ ] README on **`project-tracker-test`** says it is testing.  
- [ ] Collaborators added on both repos (if team).  
- [ ] Branch protection on **`project-tracker`** → `main` requires PR.

**When Railway uses GitHub**

- [ ] Testing Railway → connected to **`project-tracker-test`**.  
- [ ] Production Railway → connected to **`project-tracker`**.  
- [ ] Railway authorized on GitHub (Applications / Installed GitHub Apps).

**Later (optional)**

- [ ] GitHub Environments + Actions secrets when you automate deploy.  
- [ ] Dependabot enabled.

---

## Reference

- App URLs, Supabase, Firebase Hosting targets: **`ENVIRONMENTS.md`**
