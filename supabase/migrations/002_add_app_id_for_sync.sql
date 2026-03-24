-- Add app_id to teams and staff so Flutter app can map its ids (e.g. 'alumni', 'may') to Supabase UUIDs.
-- Run this only if 001 was already applied (tables exist). Safe to run multiple times.

ALTER TABLE teams ADD COLUMN IF NOT EXISTS app_id text;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS app_id text;

-- Add unique constraint only if it doesn't exist (avoids error when re-running)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'teams_app_id_key'
  ) THEN
    ALTER TABLE teams ADD CONSTRAINT teams_app_id_key UNIQUE (app_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'staff_app_id_key'
  ) THEN
    ALTER TABLE staff ADD CONSTRAINT staff_app_id_key UNIQUE (app_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_teams_app_id ON teams(app_id) WHERE app_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_staff_app_id ON staff(app_id) WHERE app_id IS NOT NULL;

COMMENT ON COLUMN teams.app_id IS 'Flutter app team id, e.g. alumni, fundraising, advancement_intel';
COMMENT ON COLUMN staff.app_id IS 'Flutter app assignee id, e.g. may, olive, janice, ken, monica, funa, ...';
