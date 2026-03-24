# Import `user level tables v1.xlsx` into Supabase

## What was generated

From your Excel workbook (sheets: `staff`, `teams`, `roles`, `subordinate_mapping`, `user_role_mapping`):

| Excel | Supabase |
|--------|-----------|
| `staff` (loginID, username) | `staff` (`app_id` from email local-part, `name`, `email`) |
| `teams` (4 teams) | `teams` — `fundraising`, `alumni`, `advancement_intel`, **`admin_team`** |
| `roles` | `roles` — `sys_admin`, `dept_head`, `supervisor`, `general` (idempotent insert) |
| `subordinate_mapping` | `subordinate_mapping` (replaces **all** rows) |
| *(no sheet)* | **`team_members`** — **derived** from subordinate edges: supervisors → `director`, subordinates → `officer` (same team) |
| `user_role_mapping` | `user_role_mapping` — only where an **`app_users`** row exists with the **same email** (Firebase-linked) |

There is **no** separate `team_members` sheet in the workbook; membership is inferred from supervisor/subordinate pairs per team.

## Files

- **`migrations/016_import_user_level_tables_v1.sql`** — run once in Supabase SQL Editor (after backup).
- **`user_level_dump.json`** — copy of the Excel data used to generate the SQL (regenerate with `node scripts/generate_import_user_level_sql.js`).
- **`scripts/generate_import_user_level_sql.js`** — regenerates the migration from `user_level_dump.json`.

## Regenerate from the Excel file

1. Install deps: `cd supabase && npm install`
2. Copy or update the workbook to match the expected sheet names, then either:
   - Run Node one-liner to refresh `user_level_dump.json`:

   ```powershell
   cd supabase
   node -e "const X=require('xlsx');const fs=require('fs');const wb=X.readFile('PATH/TO/user level tables v1.xlsx');const o={};wb.SheetNames.forEach(n=>o[n]=X.utils.sheet_to_json(wb.Sheets[n]));fs.writeFileSync('user_level_dump.json',JSON.stringify(o,null,2));"
   ```

3. `node scripts/generate_import_user_level_sql.js`

## Warnings

- **`DELETE FROM subordinate_mapping`** and **`DELETE FROM team_members`** remove existing rows before insert. If you need to **merge** instead, edit the SQL or take a DB backup first.
- **`user_role_mapping`** does not create **`app_users`**; those come from Firebase Auth + your onboarding SQL. Users without `app_users` rows are skipped.
- **`admin_team`** has no rows in `subordinate_mapping` in v1; it may have **no** `team_members` until you add supervisor/subordinate data for that team.

## Apply

1. **Back up** the project (Supabase backup or snapshot).
2. Supabase → **SQL Editor** → paste **`016_import_user_level_tables_v1.sql`** → **Run**.
