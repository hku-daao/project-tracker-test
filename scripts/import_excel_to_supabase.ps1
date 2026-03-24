# PowerShell script to read Excel file and generate Supabase migration SQL
# Requires: ImportExcel module (Install-Module -Name ImportExcel)

$excelPath = "c:\Users\calvin\The University Of Hong Kong\CRM 2.0 - Documents\General\AI\Project Tracker\user level tables v1.xlsx"
$outputPath = "c:\Users\calvin\OneDrive - The University Of Hong Kong\Documents\Cursor AI\Project Tracker\supabase\migrations\012_import_excel_data_exact_match.sql"

# Check if ImportExcel module is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "Installing ImportExcel module..." -ForegroundColor Yellow
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}

Import-Module ImportExcel

if (-not (Test-Path $excelPath)) {
    Write-Host "Error: Excel file not found: $excelPath" -ForegroundColor Red
    exit 1
}

Write-Host "Reading Excel file: $excelPath" -ForegroundColor Green

$sql = @"
-- ========================================
-- Import Excel data with exact column matching
-- File: user level tables v1.xlsx
-- Generated automatically from Excel file
-- ========================================

-- ========== STEP 1: ALTER TABLES TO MATCH EXCEL COLUMNS ==========

-- Add Excel columns to staff table if they don't exist
DO `$`$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'userid') THEN
        ALTER TABLE staff ADD COLUMN userid text;
    END IF;
    -- Create unique constraint on userid if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'staff_userid_key') THEN
        BEGIN
            ALTER TABLE staff ADD CONSTRAINT staff_userid_key UNIQUE (userid);
        EXCEPTION WHEN duplicate_object THEN
            -- Constraint might exist with different name
            NULL;
        END;
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
    
    -- Add hashedpwd column if it exists in Excel
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'staff' AND column_name = 'hashedpwd') THEN
        ALTER TABLE staff ADD COLUMN hashedpwd text;
    END IF;
END `$`$;

-- Add Excel columns to teams table if they don't exist
DO `$`$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'teams' AND column_name = 'teamid') THEN
        ALTER TABLE teams ADD COLUMN teamid text;
    END IF;
    -- Create unique constraint on teamid if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'teams_teamid_key') THEN
        BEGIN
            ALTER TABLE teams ADD CONSTRAINT teams_teamid_key UNIQUE (teamid);
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        END;
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
END `$`$;

-- Add Excel columns to roles table if they don't exist
DO `$`$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'roles' AND column_name = 'roleid') THEN
        ALTER TABLE roles ADD COLUMN roleid text;
    END IF;
    -- Create unique constraint on roleid if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'roles_roleid_key') THEN
        BEGIN
            ALTER TABLE roles ADD CONSTRAINT roles_roleid_key UNIQUE (roleid);
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        END;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'roles' AND column_name = 'role') THEN
        ALTER TABLE roles ADD COLUMN role text;
    END IF;
END `$`$;

-- ========== STEP 2: IMPORT DATA FROM EXCEL ==========

"@

# Function to quote column names that need it (mixed case)
function Quote-ColumnName($colName) {
    # Quote if it has mixed case (like loginID) or starts with uppercase
    if ($colName -cmatch '[A-Z]' -and $colName -cmatch '[a-z]') {
        return "`"$colName`""
    }
    return $colName
}

# Process staff worksheet
Write-Host "Processing staff worksheet..." -ForegroundColor Cyan
try {
    $staffData = Import-Excel -Path $excelPath -WorksheetName "staff"
    $staffColumns = $staffData[0].PSObject.Properties.Name
    Write-Host "  Columns: $($staffColumns -join ', ')" -ForegroundColor Gray
    
    $sql += "`n-- ========== STAFF ==========`n"
    $sql += "-- Excel columns: $($staffColumns -join ', ')`n`n"
    
    foreach ($row in $staffData) {
        $values = @()
        $cols = @()
        $quotedCols = @()
        
        # Map Excel 'username' to Supabase 'name' (required NOT NULL column)
        $nameValue = if ($staffColumns -contains 'username') {
            $row.username
        } elseif ($staffColumns -contains 'name') {
            $row.name
        } else {
            '' # Fallback
        }
        
        # Always include 'name' column first (required)
        if ($nameValue -and $nameValue.ToString().Trim() -ne '') {
            $escaped = $nameValue.ToString().Replace("'", "''")
            $values += "'$escaped'"
        } else {
            $values += "NULL"
        }
        $cols += 'name'
        $quotedCols += 'name'
        
        # Add all Excel columns
        foreach ($col in $staffColumns) {
            $val = $row.$col
            if ($null -eq $val -or $val -eq '') {
                $values += "NULL"
            } else {
                $escaped = $val.ToString().Replace("'", "''")
                $values += "'$escaped'"
            }
            $cols += $col
            $quotedCols += Quote-ColumnName $col
        }
        
        # Use app_id as conflict key (has unique constraint), fallback to userid (will have unique constraint)
        $conflictKey = if ($cols -contains 'app_id') { Quote-ColumnName 'app_id' } elseif ($cols -contains 'userid') { Quote-ColumnName 'userid' } else { Quote-ColumnName $cols[0] }
        $updateCols = $cols | Where-Object { 
            $col = $_
            $conflictCol = if ($cols -contains 'app_id') { 'app_id' } elseif ($cols -contains 'userid') { 'userid' } else { $cols[0] }
            $col -ne $conflictCol
        }
        
        $sql += "INSERT INTO staff ($($quotedCols -join ', '))`n"
        $sql += "VALUES ($($values -join ', '))`n"
        $sql += "ON CONFLICT ($conflictKey) DO UPDATE SET`n"
        $updateStr = ($updateCols | ForEach-Object { "$(Quote-ColumnName $_) = EXCLUDED.$(Quote-ColumnName $_)" }) -join ",`n  "
        $sql += "  $updateStr;`n`n"
    }
} catch {
    Write-Host "  Error processing staff: $_" -ForegroundColor Red
}

# Process teams worksheet
Write-Host "Processing teams worksheet..." -ForegroundColor Cyan
try {
    $teamsData = Import-Excel -Path $excelPath -WorksheetName "teams"
    $teamsColumns = $teamsData[0].PSObject.Properties.Name
    Write-Host "  Columns: $($teamsColumns -join ', ')" -ForegroundColor Gray
    
    $sql += "`n-- ========== TEAMS ==========`n"
    $sql += "-- Excel columns: $($teamsColumns -join ', ')`n`n"
    
    foreach ($row in $teamsData) {
        $values = @()
        $cols = @()
        $quotedCols = @()
        
        # Map Excel 'team' to Supabase 'name' (required NOT NULL column)
        $nameValue = if ($teamsColumns -contains 'team') {
            $row.team
        } elseif ($teamsColumns -contains 'name') {
            $row.name
        } else {
            '' # Fallback
        }
        
        # Always include 'name' column first (required)
        if ($nameValue -and $nameValue.ToString().Trim() -ne '') {
            $escaped = $nameValue.ToString().Replace("'", "''")
            $values += "'$escaped'"
        } else {
            $values += "NULL"
        }
        $cols += 'name'
        $quotedCols += 'name'
        
        # Add all Excel columns
        foreach ($col in $teamsColumns) {
            $val = $row.$col
            if ($null -eq $val -or $val -eq '') {
                $values += "NULL"
            } else {
                $escaped = $val.ToString().Replace("'", "''")
                $values += "'$escaped'"
            }
            $cols += $col
            $quotedCols += Quote-ColumnName $col
        }
        
        $conflictKey = if ($cols -contains 'app_id') { Quote-ColumnName 'app_id' } elseif ($cols -contains 'teamid') { Quote-ColumnName 'teamid' } else { Quote-ColumnName $cols[0] }
        $updateCols = $cols | Where-Object { 
            $col = $_
            $conflictCol = if ($cols -contains 'app_id') { 'app_id' } elseif ($cols -contains 'teamid') { 'teamid' } else { $cols[0] }
            $col -ne $conflictCol
        }
        
        $sql += "INSERT INTO teams ($($quotedCols -join ', '))`n"
        $sql += "VALUES ($($values -join ', '))`n"
        $sql += "ON CONFLICT ($conflictKey) DO UPDATE SET`n"
        $updateStr = ($updateCols | ForEach-Object { "$(Quote-ColumnName $_) = EXCLUDED.$(Quote-ColumnName $_)" }) -join ",`n  "
        $sql += "  $updateStr;`n`n"
    }
} catch {
    Write-Host "  Error processing teams: $_" -ForegroundColor Red
}

# Process roles worksheet
Write-Host "Processing roles worksheet..." -ForegroundColor Cyan
try {
    $rolesData = Import-Excel -Path $excelPath -WorksheetName "roles"
    $rolesColumns = $rolesData[0].PSObject.Properties.Name
    Write-Host "  Columns: $($rolesColumns -join ', ')" -ForegroundColor Gray
    
    $sql += "`n-- ========== ROLES ==========`n"
    $sql += "-- Excel columns: $($rolesColumns -join ', ')`n`n"
    
    foreach ($row in $rolesData) {
        $values = @()
        $cols = @()
        $quotedCols = @()
        
        # Map Excel 'role' to Supabase 'name' (required NOT NULL column)
        $nameValue = if ($rolesColumns -contains 'role') {
            $row.role
        } elseif ($rolesColumns -contains 'name') {
            $row.name
        } else {
            '' # Fallback
        }
        
        # Map Excel 'role' to Supabase 'app_id' (required NOT NULL column)
        # Convert "sys admin" -> "sys_admin", "dept head" -> "dept_head", etc.
        $appIdValue = if ($rolesColumns -contains 'role') {
            $roleVal = $row.role
            if ($roleVal) {
                $roleVal.ToString().ToLower().Replace(' ', '_')
            } else {
                ''
            }
        } elseif ($rolesColumns -contains 'app_id') {
            $row.app_id
        } else {
            '' # Fallback
        }
        
        # Always include 'name' column first (required)
        if ($nameValue -and $nameValue.ToString().Trim() -ne '') {
            $escaped = $nameValue.ToString().Replace("'", "''")
            $values += "'$escaped'"
        } else {
            $values += "NULL"
        }
        $cols += 'name'
        $quotedCols += 'name'
        
        # Always include 'app_id' column second (required)
        if ($appIdValue -and $appIdValue.ToString().Trim() -ne '') {
            $escaped = $appIdValue.ToString().Replace("'", "''")
            $values += "'$escaped'"
        } else {
            $values += "NULL"
        }
        $cols += 'app_id'
        $quotedCols += 'app_id'
        
        # Add all Excel columns
        foreach ($col in $rolesColumns) {
            $val = $row.$col
            if ($null -eq $val -or $val -eq '') {
                $values += "NULL"
            } else {
                $escaped = $val.ToString().Replace("'", "''")
                $values += "'$escaped'"
            }
            $cols += $col
            $quotedCols += Quote-ColumnName $col
        }
        
        $conflictKey = if ($cols -contains 'app_id') { Quote-ColumnName 'app_id' } elseif ($cols -contains 'roleid') { Quote-ColumnName 'roleid' } else { Quote-ColumnName $cols[0] }
        $updateCols = $cols | Where-Object { 
            $col = $_
            $conflictCol = if ($cols -contains 'app_id') { 'app_id' } elseif ($cols -contains 'roleid') { 'roleid' } else { $cols[0] }
            $col -ne $conflictCol
        }
        
        $sql += "INSERT INTO roles ($($quotedCols -join ', '))`n"
        $sql += "VALUES ($($values -join ', '))`n"
        $sql += "ON CONFLICT ($conflictKey) DO UPDATE SET`n"
        $updateStr = ($updateCols | ForEach-Object { "$(Quote-ColumnName $_) = EXCLUDED.$(Quote-ColumnName $_)" }) -join ",`n  "
        $sql += "  $updateStr;`n`n"
    }
} catch {
    Write-Host "  Error processing roles: $_" -ForegroundColor Red
}

# Process subordinate_mapping worksheet
Write-Host "Processing subordinate_mapping worksheet..." -ForegroundColor Cyan
try {
    $subData = Import-Excel -Path $excelPath -WorksheetName "subordinate_mapping"
    $subColumns = $subData[0].PSObject.Properties.Name
    Write-Host "  Columns: $($subColumns -join ', ')" -ForegroundColor Gray
    
    $sql += "`n-- ========== SUBORDINATE MAPPING ==========`n"
    $sql += "-- Excel columns: $($subColumns -join ', ')`n`n"
    
    # Find supervisor and subordinate columns
    $superCol = $subColumns | Where-Object { $_ -like '*super*' -or $_ -like '*supervisor*' } | Select-Object -First 1
    $subCol = $subColumns | Where-Object { $_ -like '*sub*' -or $_ -like '*subordinate*' } | Select-Object -First 1
    
    if ($superCol -and $subCol) {
        foreach ($row in $subData) {
            $superVal = $row.$superCol
            $subVal = $row.$subCol
            if ($superVal -and $subVal) {
                $superEscaped = $superVal.ToString().Replace("'", "''")
                $subEscaped = $subVal.ToString().Replace("'", "''")
                $sql += "INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)`n"
                $sql += "SELECT s1.id, s2.id`n"
                $sql += "FROM staff s1, staff s2`n"
                $sql += "WHERE s1.userid = '$superEscaped' AND s2.userid = '$subEscaped'`n"
                $sql += "ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;`n`n"
            }
        }
    } else {
        $sql += "-- ERROR: Could not find supervisor and subordinate columns`n"
        $sql += "-- Available columns: $($subColumns -join ', ')`n"
    }
} catch {
    Write-Host "  Error processing subordinate_mapping: $_" -ForegroundColor Red
}

# Process user_role_mapping worksheet
Write-Host "Processing user_role_mapping worksheet..." -ForegroundColor Cyan
try {
    $urmData = Import-Excel -Path $excelPath -WorksheetName "user_role_mapping"
    $urmColumns = $urmData[0].PSObject.Properties.Name
    Write-Host "  Columns: $($urmColumns -join ', ')" -ForegroundColor Gray
    
    $sql += "`n-- ========== USER ROLE MAPPING ==========`n"
    $sql += "-- Excel columns: $($urmColumns -join ', ')`n`n"
    
    # Find userid and roleid columns
    $useridCol = $urmColumns | Where-Object { $_ -like '*userid*' -or $_ -like '*user_id*' } | Select-Object -First 1
    $roleidCol = $urmColumns | Where-Object { $_ -like '*roleid*' -or $_ -like '*role_id*' } | Select-Object -First 1
    
    if ($useridCol -and $roleidCol) {
        foreach ($row in $urmData) {
            $useridVal = $row.$useridCol
            $roleidVal = $row.$roleidCol
            if ($useridVal -and $roleidVal) {
                $useridEscaped = $useridVal.ToString().Replace("'", "''")
                $roleidEscaped = $roleidVal.ToString().Replace("'", "''")
                $sql += "INSERT INTO user_role_mapping (app_user_id, role_id)`n"
                $sql += "SELECT au.id, r.id`n"
                $sql += "FROM app_users au`n"
                $sql += "JOIN staff s ON s.id = au.staff_id`n"
                $sql += "JOIN roles r ON r.roleid = '$roleidEscaped'`n"
                $sql += "WHERE s.userid = '$useridEscaped'`n"
                $sql += "ON CONFLICT (app_user_id, role_id) DO NOTHING;`n`n"
            }
        }
    } else {
        $sql += "-- ERROR: Could not find userid and roleid columns`n"
        $sql += "-- Available columns: $($urmColumns -join ', ')`n"
    }
} catch {
    Write-Host "  Error processing user_role_mapping: $_" -ForegroundColor Red
}

$sql += "`n-- ========================================`n"
$sql += "-- End of import script`n"
$sql += "-- ========================================`n"

# Write output
$outputDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$sql | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "`nSQL migration generated: $outputPath" -ForegroundColor Green
Write-Host "Review the file and run it in Supabase SQL Editor" -ForegroundColor Yellow
