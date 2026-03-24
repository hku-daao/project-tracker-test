# Excel to Supabase Import Guide

This guide helps you import data from `user level tables v1.xlsx` into Supabase tables, ensuring column names and values match the Excel file exactly.

## Excel Worksheets

The Excel file contains 5 worksheets:
1. **staff** - Staff members
2. **teams** - Teams
3. **roles** - User roles
4. **subordinate_mapping** - Supervisor-subordinate relationships
5. **user_role_mapping** - User-role assignments

## Steps to Import

### Option 1: Use PowerShell Script (Recommended)

1. Open PowerShell in the project directory
2. Run:
   ```powershell
   .\scripts\import_excel_to_supabase.ps1
   ```
3. The script will:
   - Install ImportExcel module if needed
   - Read all 5 worksheets from the Excel file
   - Generate SQL migration file: `supabase/migrations/012_import_excel_data_exact_match.sql`
4. Review the generated SQL file
5. Run it in Supabase SQL Editor

### Option 2: Manual Import

1. Open the Excel file: `user level tables v1.xlsx`
2. For each worksheet, copy the data
3. Use the template in `supabase/migrations/012_import_excel_data_exact_match.sql`
4. Replace the example INSERT statements with your actual data
5. Ensure column names match exactly (case-sensitive)
6. Run in Supabase SQL Editor

## Column Mapping

### Staff Table
- Excel columns: `userid`, `loginID`, `username`, `chinesename`, `active`
- Supabase columns: All Excel columns + `id` (UUID), `name`, `app_id` (from existing schema)

### Teams Table
- Excel columns: `teamid`, `dept`, `team`, `active`
- Supabase columns: All Excel columns + `id` (UUID), `name`, `app_id` (from existing schema)

### Roles Table
- Excel columns: `roleid`, `role`
- Supabase columns: All Excel columns + `id` (UUID), `name`, `app_id` (from existing schema)

### Subordinate Mapping Table
- Excel columns: `smapid`, `teamid`, `super_id`, `subo_id`, `active`
- Supabase columns: `supervisor_staff_id` (UUID from staff.userid), `subordinate_staff_id` (UUID from staff.userid)

### User Role Mapping Table
- Excel columns: `urmapid`, `userid`, `roleid`
- Supabase columns: `app_user_id` (UUID from app_users via staff.userid), `role_id` (UUID from roles.roleid)

## Important Notes

1. **Column Names**: Must match Excel exactly (case-sensitive: `loginID` not `loginid`)
2. **Values**: Must match Excel exactly
3. **UUIDs**: Supabase uses UUIDs, but Excel uses IDs - the migration maps them automatically
4. **Conflicts**: Uses `ON CONFLICT` to update existing records
5. **Verification**: Always verify the imported data matches your Excel file

## Troubleshooting

- If PowerShell script fails, ensure you have admin rights or install ImportExcel manually:
  ```powershell
  Install-Module -Name ImportExcel -Scope CurrentUser
  ```
- If column names don't match, check for typos or extra spaces
- If data doesn't import, check that UUIDs are correctly mapped
