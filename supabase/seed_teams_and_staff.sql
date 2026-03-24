-- Seed teams and staff with app_id so Flutter can sync initiatives.
-- Run 001_initial_schema.sql and 002_add_app_id_for_sync.sql first, then run this in SQL Editor.
-- If you get "no unique constraint" error, run 002_add_app_id_for_sync.sql first (adds app_id UNIQUE).

-- Teams (app_id must match Flutter: alumni, fundraising, advancement_intel)
INSERT INTO teams (id, name, app_id) VALUES
  (gen_random_uuid(), 'Alumni Team', 'alumni'),
  (gen_random_uuid(), 'Fundraising Team', 'fundraising'),
  (gen_random_uuid(), 'Advancement Intelligence Team', 'advancement_intel')
ON CONFLICT (app_id) DO NOTHING;

-- Staff (app_id must match Flutter assignee ids)
-- Directors
INSERT INTO staff (id, name, app_id) VALUES
  (gen_random_uuid(), 'May Wong', 'may'),
  (gen_random_uuid(), 'Olive Wong', 'olive'),
  (gen_random_uuid(), 'Janice Chan', 'janice'),
  (gen_random_uuid(), 'Ken Lee', 'ken'),
  (gen_random_uuid(), 'Monica Wong', 'monica')
ON CONFLICT (app_id) DO NOTHING;

-- Alumni Team – Responsible Officers
INSERT INTO staff (id, name, app_id) VALUES
  (gen_random_uuid(), 'Funa Li', 'funa'),
  (gen_random_uuid(), 'Anthony Tai', 'anthony_tai'),
  (gen_random_uuid(), 'Holly Tang', 'holly_tang'),
  (gen_random_uuid(), 'Sally Oh Yea Won', 'sally_oh'),
  (gen_random_uuid(), 'Sally Cheng', 'sally_cheng'),
  (gen_random_uuid(), 'Rui Wang', 'rui_wang'),
  (gen_random_uuid(), 'I Ki Chan', 'i_ki_chan'),
  (gen_random_uuid(), 'Janelle Wong', 'janelle_wong'),
  (gen_random_uuid(), 'Carol Luk', 'carol_luk')
ON CONFLICT (app_id) DO NOTHING;

-- Fundraising Team – Responsible Officers
INSERT INTO staff (id, name, app_id) VALUES
  (gen_random_uuid(), 'Charlotte Siu', 'charlotte_siu'),
  (gen_random_uuid(), 'Eva Tang', 'eva_tang'),
  (gen_random_uuid(), 'Katerina Au', 'katerina'),
  (gen_random_uuid(), 'Elaine Lam', 'elaine_lam'),
  (gen_random_uuid(), 'Judi Tsang', 'judi_tsang'),
  (gen_random_uuid(), 'Kelly Lee', 'kelly_lee'),
  (gen_random_uuid(), 'Melody Tang', 'melody_tang'),
  (gen_random_uuid(), 'Aura Lu', 'aura_lu')
ON CONFLICT (app_id) DO NOTHING;

-- Advancement Intelligence Team – Responsible Officers
INSERT INTO staff (id, name, app_id) VALUES
  (gen_random_uuid(), 'Calvin Lee', 'calvin_lee'),
  (gen_random_uuid(), 'Lunan Chow', 'lunan_chow'),
  (gen_random_uuid(), 'Ken Wong', 'ken_wong'),
  (gen_random_uuid(), 'Wai-kay Pang', 'waikay_pang')
ON CONFLICT (app_id) DO NOTHING;
