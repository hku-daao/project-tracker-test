-- Some databases have team_members(team_id, staff_id) without a role column.
-- Backend /api/teams and seeds expect team_members.role (director | officer).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'team_members'
      AND column_name = 'role'
  ) THEN
    ALTER TABLE public.team_members ADD COLUMN role text;
    -- Default existing rows so UI can classify members
    UPDATE public.team_members SET role = 'officer' WHERE role IS NULL;
  END IF;
END $$;

-- Allow director, officer, and legacy aliases used in older code
ALTER TABLE public.team_members DROP CONSTRAINT IF EXISTS team_members_role_check;
ALTER TABLE public.team_members
  ADD CONSTRAINT team_members_role_check
  CHECK (role IS NULL OR role IN ('director', 'officer', 'lead', 'member'));

COMMENT ON COLUMN public.team_members.role IS 'director or officer (lead/member accepted as legacy aliases)';
