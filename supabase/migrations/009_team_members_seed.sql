-- Populate team_members so get_assignable_staff returns team info. Matches Flutter AppState.teams.
-- Run after 002 and seed_teams_and_staff (teams and staff have app_id).

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'director'
FROM teams t, staff s
WHERE t.app_id = 'alumni' AND s.app_id IN ('monica')
ON CONFLICT (team_id, staff_id) DO NOTHING;

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'officer'
FROM teams t, staff s
WHERE t.app_id = 'alumni' AND s.app_id IN (
  'funa','anthony_tai','holly_tang','sally_oh','sally_cheng','rui_wang',
  'i_ki_chan','janelle_wong','carol_luk'
)
ON CONFLICT (team_id, staff_id) DO NOTHING;

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'director'
FROM teams t, staff s
WHERE t.app_id = 'fundraising' AND s.app_id IN ('may','olive','janice')
ON CONFLICT (team_id, staff_id) DO NOTHING;

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'officer'
FROM teams t, staff s
WHERE t.app_id = 'fundraising' AND s.app_id IN (
  'charlotte_siu','eva_tang','katerina','elaine_lam','judi_tsang',
  'kelly_lee','melody_tang','aura_lu'
)
ON CONFLICT (team_id, staff_id) DO NOTHING;

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'director'
FROM teams t, staff s
WHERE t.app_id = 'advancement_intel' AND s.app_id IN ('ken')
ON CONFLICT (team_id, staff_id) DO NOTHING;

INSERT INTO team_members (team_id, staff_id, role)
SELECT t.id, s.id, 'officer'
FROM teams t, staff s
WHERE t.app_id = 'advancement_intel' AND s.app_id IN ('calvin_lee','lunan_chow','ken_wong','waikay_pang')
ON CONFLICT (team_id, staff_id) DO NOTHING;

-- Alumni Affairs (4th team): if you added staff for it, add similar inserts; else skip.
-- INSERT INTO team_members ... WHERE t.app_id = 'alumni_affairs' ...
