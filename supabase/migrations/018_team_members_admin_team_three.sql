-- =============================================================================
-- Add three staff members to Admin Team (team_members)
--
-- Team:  d555f75f-bf8c-4519-9740-02acee9194b6 (Admin Team)
-- Staff: ronnielee@hku.hk, alanl@hku.hk, csmfung@hku.hk
--
-- Role: officer (change to 'director' in this file if you prefer for Admin Team)
-- Requires: migration 015 (team_members.role) or equivalent CHECK allowing director|officer
-- =============================================================================

INSERT INTO team_members (team_id, staff_id, role)
VALUES
  ('d555f75f-bf8c-4519-9740-02acee9194b6'::uuid, '65da5b55-5b83-46be-bc95-15ad50651cdd'::uuid, 'officer'),
  ('d555f75f-bf8c-4519-9740-02acee9194b6'::uuid, '23c93569-4c5a-486a-b93a-5b06fcfb7382'::uuid, 'officer'),
  ('d555f75f-bf8c-4519-9740-02acee9194b6'::uuid, 'ecad1380-c047-4ab3-bbf8-b69b799b4574'::uuid, 'officer')
ON CONFLICT (team_id, staff_id) DO UPDATE SET
  role = EXCLUDED.role;
