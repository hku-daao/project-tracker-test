#!/usr/bin/env python3
"""
Read Excel file and generate Supabase migration SQL.
Excel file: user level tables v1.xlsx
Worksheets: staff, teams, roles, subordinate_mapping, user_role_mapping
"""

import pandas as pd
import sys
import os
from pathlib import Path

# Path to Excel file
EXCEL_PATH = r"c:\Users\calvin\The University Of Hong Kong\CRM 2.0 - Documents\General\AI\Project Tracker\user level tables v1.xlsx"
OUTPUT_PATH = Path(__file__).parent.parent / "supabase" / "migrations" / "012_import_excel_data_v2.sql"

def escape_sql_string(value):
    """Escape SQL string values"""
    if value is None or pd.isna(value):
        return 'NULL'
    if isinstance(value, (int, float)):
        return str(value)
    # Escape single quotes
    return "'" + str(value).replace("'", "''") + "'"

def generate_staff_sql(df):
    """Generate SQL for staff table"""
    sql = "-- ========== STAFF ==========\n"
    sql += "-- Excel columns: " + ", ".join(df.columns.tolist()) + "\n\n"
    
    for _, row in df.iterrows():
        # Get all columns from Excel
        values = {}
        for col in df.columns:
            val = row[col]
            if pd.isna(val):
                values[col] = None
            else:
                values[col] = val
        
        # Build INSERT statement with all Excel columns
        cols = list(df.columns)
        vals = [escape_sql_string(values.get(col)) for col in cols]
        
        # Use app_id as conflict key (or userid if app_id doesn't exist)
        conflict_key = 'app_id' if 'app_id' in cols else ('userid' if 'userid' in cols else cols[0])
        
        sql += f"INSERT INTO staff ({', '.join(cols)})\n"
        sql += f"VALUES ({', '.join(vals)})\n"
        sql += f"ON CONFLICT ({conflict_key}) DO UPDATE SET\n"
        
        # Update all columns except the conflict key
        update_cols = [col for col in cols if col != conflict_key]
        updates = [f"  {col} = EXCLUDED.{col}" for col in update_cols]
        sql += ",\n".join(updates) + ";\n\n"
    
    return sql

def generate_teams_sql(df):
    """Generate SQL for teams table"""
    sql = "-- ========== TEAMS ==========\n"
    sql += "-- Excel columns: " + ", ".join(df.columns.tolist()) + "\n\n"
    
    for _, row in df.iterrows():
        values = {}
        for col in df.columns:
            val = row[col]
            if pd.isna(val):
                values[col] = None
            else:
                values[col] = val
        
        cols = list(df.columns)
        vals = [escape_sql_string(values.get(col)) for col in cols]
        
        conflict_key = 'app_id' if 'app_id' in cols else ('teamid' if 'teamid' in cols else cols[0])
        
        sql += f"INSERT INTO teams ({', '.join(cols)})\n"
        sql += f"VALUES ({', '.join(vals)})\n"
        sql += f"ON CONFLICT ({conflict_key}) DO UPDATE SET\n"
        
        update_cols = [col for col in cols if col != conflict_key]
        updates = [f"  {col} = EXCLUDED.{col}" for col in update_cols]
        sql += ",\n".join(updates) + ";\n\n"
    
    return sql

def generate_roles_sql(df):
    """Generate SQL for roles table"""
    sql = "-- ========== ROLES ==========\n"
    sql += "-- Excel columns: " + ", ".join(df.columns.tolist()) + "\n\n"
    
    for _, row in df.iterrows():
        values = {}
        for col in df.columns:
            val = row[col]
            if pd.isna(val):
                values[col] = None
            else:
                values[col] = val
        
        cols = list(df.columns)
        vals = [escape_sql_string(values.get(col)) for col in cols]
        
        conflict_key = 'app_id' if 'app_id' in cols else ('roleid' if 'roleid' in cols else cols[0])
        
        sql += f"INSERT INTO roles ({', '.join(cols)})\n"
        sql += f"VALUES ({', '.join(vals)})\n"
        sql += f"ON CONFLICT ({conflict_key}) DO UPDATE SET\n"
        
        update_cols = [col for col in cols if col != conflict_key]
        updates = [f"  {col} = EXCLUDED.{col}" for col in update_cols]
        sql += ",\n".join(updates) + ";\n\n"
    
    return sql

def generate_subordinate_mapping_sql(df):
    """Generate SQL for subordinate_mapping table"""
    sql = "-- ========== SUBORDINATE MAPPING ==========\n"
    sql += "-- Excel columns: " + ", ".join(df.columns.tolist()) + "\n\n"
    
    # Map Excel columns to Supabase columns
    # Excel: super_id, subo_id -> Supabase: supervisor_staff_id, subordinate_staff_id
    supervisor_col = None
    subordinate_col = None
    
    for col in df.columns:
        col_lower = str(col).lower()
        if 'super' in col_lower or 'supervisor' in col_lower:
            supervisor_col = col
        if 'sub' in col_lower or 'subordinate' in col_lower:
            subordinate_col = col
    
    if not supervisor_col or not subordinate_col:
        sql += "-- ERROR: Could not find supervisor and subordinate columns\n"
        sql += f"-- Available columns: {', '.join(df.columns.tolist())}\n"
        return sql
    
    for _, row in df.iterrows():
        supervisor_val = row[supervisor_col]
        subordinate_val = row[subordinate_col]
        
        if pd.isna(supervisor_val) or pd.isna(subordinate_val):
            continue
        
        sql += f"INSERT INTO subordinate_mapping (supervisor_staff_id, subordinate_staff_id)\n"
        sql += f"SELECT s1.id, s2.id\n"
        sql += f"FROM staff s1, staff s2\n"
        sql += f"WHERE s1.userid = {escape_sql_string(supervisor_val)}\n"
        sql += f"  AND s2.userid = {escape_sql_string(subordinate_val)}\n"
        sql += f"ON CONFLICT (supervisor_staff_id, subordinate_staff_id) DO NOTHING;\n\n"
    
    return sql

def generate_user_role_mapping_sql(df):
    """Generate SQL for user_role_mapping table"""
    sql = "-- ========== USER ROLE MAPPING ==========\n"
    sql += "-- Excel columns: " + ", ".join(df.columns.tolist()) + "\n\n"
    
    # Map Excel columns to Supabase columns
    # Excel: userid, roleid -> Supabase: app_user_id (from staff.userid), role_id (from roles.roleid)
    userid_col = None
    roleid_col = None
    
    for col in df.columns:
        col_lower = str(col).lower()
        if 'userid' in col_lower or 'user_id' in col_lower:
            userid_col = col
        if 'roleid' in col_lower or 'role_id' in col_lower:
            roleid_col = col
    
    if not userid_col or not roleid_col:
        sql += "-- ERROR: Could not find userid and roleid columns\n"
        sql += f"-- Available columns: {', '.join(df.columns.tolist())}\n"
        return sql
    
    for _, row in df.iterrows():
        userid_val = row[userid_col]
        roleid_val = row[roleid_col]
        
        if pd.isna(userid_val) or pd.isna(roleid_val):
            continue
        
        sql += f"INSERT INTO user_role_mapping (app_user_id, role_id)\n"
        sql += f"SELECT au.id, r.id\n"
        sql += f"FROM app_users au\n"
        sql += f"JOIN staff s ON s.id = au.staff_id\n"
        sql += f"JOIN roles r ON r.roleid = {escape_sql_string(roleid_val)}\n"
        sql += f"WHERE s.userid = {escape_sql_string(userid_val)}\n"
        sql += f"ON CONFLICT (app_user_id, role_id) DO NOTHING;\n\n"
    
    return sql

def main():
    if not os.path.exists(EXCEL_PATH):
        print(f"Error: Excel file not found: {EXCEL_PATH}")
        sys.exit(1)
    
    print(f"Reading Excel file: {EXCEL_PATH}")
    
    # Read all worksheets
    excel_file = pd.ExcelFile(EXCEL_PATH)
    
    sql_output = "-- ========================================\n"
    sql_output += "-- Import script generated from Excel file\n"
    sql_output += f"-- File: {os.path.basename(EXCEL_PATH)}\n"
    sql_output += "-- ========================================\n\n"
    
    # Process each worksheet
    worksheets = {
        'staff': generate_staff_sql,
        'teams': generate_teams_sql,
        'roles': generate_roles_sql,
        'subordinate_mapping': generate_subordinate_mapping_sql,
        'user_role_mapping': generate_user_role_mapping_sql,
    }
    
    for sheet_name, generator_func in worksheets.items():
        if sheet_name not in excel_file.sheet_names:
            print(f"Warning: Worksheet '{sheet_name}' not found in Excel file")
            continue
        
        print(f"Processing worksheet: {sheet_name}")
        df = pd.read_excel(excel_file, sheet_name=sheet_name)
        print(f"  Found {len(df)} rows")
        print(f"  Columns: {', '.join(df.columns.tolist())}")
        
        sql_output += generator_func(df)
        sql_output += "\n"
    
    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write(sql_output)
    
    print(f"\nSQL migration generated: {OUTPUT_PATH}")
    print("Review the file and run it in Supabase SQL Editor")

if __name__ == '__main__':
    main()
