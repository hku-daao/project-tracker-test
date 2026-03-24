-- ========================================
-- Merge loginID into email and set app_id for staff
-- ========================================

-- Step 1: Update email column with loginID values where email is NULL or empty
-- This merges loginID into email (email is the primary column)
UPDATE staff
SET email = "loginID"
WHERE "loginID" IS NOT NULL 
  AND "loginID" != ''
  AND (email IS NULL OR email = '');

-- Step 2: Assign app_id values to staff records
-- app_id is derived from email (part before @) or username
-- This ensures each staff member has a unique app_id for the Flutter app

-- Assign app_id from email (part before @, replace dots with underscores)
-- Example: 'yang.wang@hku.hk' -> 'yang_wang'
UPDATE staff
SET app_id = LOWER(REPLACE(SPLIT_PART(email, '@', 1), '.', '_'))
WHERE email IS NOT NULL 
  AND email != ''
  AND (app_id IS NULL OR app_id = '');

-- If email is not available, try to derive from username
UPDATE staff
SET app_id = LOWER(REGEXP_REPLACE(username, '[^a-zA-Z0-9]', '_', 'g'))
WHERE (app_id IS NULL OR app_id = '')
  AND username IS NOT NULL 
  AND username != '';

-- If still no app_id, use userid as fallback
UPDATE staff
SET app_id = 'staff_' || userid
WHERE (app_id IS NULL OR app_id = '')
  AND userid IS NOT NULL;

-- Ensure app_id is unique (handle duplicates by appending userid)
DO $$
DECLARE
    dup_record RECORD;
    counter INTEGER;
BEGIN
    FOR dup_record IN 
        SELECT app_id, COUNT(*) as cnt, array_agg(id::text) as ids
        FROM staff
        WHERE app_id IS NOT NULL
        GROUP BY app_id
        HAVING COUNT(*) > 1
    LOOP
        counter := 1;
        FOR i IN 2..dup_record.cnt LOOP
            UPDATE staff
            SET app_id = dup_record.app_id || '_' || userid
            WHERE id::text = ANY(dup_record.ids)
              AND app_id = dup_record.app_id
              AND id::text != (SELECT id::text FROM staff WHERE app_id = dup_record.app_id LIMIT 1);
            EXIT WHEN NOT FOUND;
        END LOOP;
    END LOOP;
END $$;

-- Step 3: Drop the loginID column (after merging to email and setting app_id)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'staff' AND column_name = 'loginID') THEN
        ALTER TABLE staff DROP COLUMN "loginID";
    END IF;
END $$;

-- Create index on app_id if it doesn't exist (should already exist from migration 002, but ensure it)
CREATE INDEX IF NOT EXISTS idx_staff_app_id ON staff(app_id) WHERE app_id IS NOT NULL;

COMMENT ON COLUMN staff.email IS 'Email address (merged from loginID, now primary email column)';
COMMENT ON COLUMN staff.app_id IS 'Flutter app assignee id, derived from email or username';
