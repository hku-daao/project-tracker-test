-- Allow anonymous (Flutter web) to read data needed to load initiatives.
-- Run in Supabase SQL Editor after enabling RLS on these tables (or if reads fail on web).

-- If RLS is off, you can skip this. If RLS is on and web shows empty list / error, run:

ALTER TABLE initiatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE initiative_directors ENABLE ROW LEVEL SECURITY;
ALTER TABLE sub_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_read_initiatives" ON initiatives;
CREATE POLICY "anon_read_initiatives" ON initiatives FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_read_teams" ON teams;
CREATE POLICY "anon_read_teams" ON teams FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_read_staff" ON staff;
CREATE POLICY "anon_read_staff" ON staff FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_read_initiative_directors" ON initiative_directors;
CREATE POLICY "anon_read_initiative_directors" ON initiative_directors FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_read_sub_tasks" ON sub_tasks;
CREATE POLICY "anon_read_sub_tasks" ON sub_tasks FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_read_comments" ON comments;
CREATE POLICY "anon_read_comments" ON comments FOR SELECT TO anon USING (true);

-- Inserts still need INSERT policies for anon (or use service role). For create initiative from app:
DROP POLICY IF EXISTS "anon_insert_initiatives" ON initiatives;
CREATE POLICY "anon_insert_initiatives" ON initiatives FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_insert_initiative_directors" ON initiative_directors;
CREATE POLICY "anon_insert_initiative_directors" ON initiative_directors FOR INSERT TO anon WITH CHECK (true);
