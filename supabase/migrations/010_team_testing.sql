-- "Testing" team for QA / admin
INSERT INTO teams (id, name, app_id) VALUES
  (gen_random_uuid(), 'Testing', 'testing')
ON CONFLICT (app_id) DO UPDATE SET name = EXCLUDED.name;
