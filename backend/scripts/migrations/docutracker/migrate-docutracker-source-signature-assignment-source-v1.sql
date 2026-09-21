BEGIN;

-- Snapshot how an RSP/L&D source signature slot was assigned so admin recovery
-- can require remarks when overriding creator or automatic assignments.

ALTER TABLE docutracker_rsp_source_signatures
  ADD COLUMN IF NOT EXISTS assignment_source TEXT NOT NULL DEFAULT 'manual';

ALTER TABLE docutracker_rsp_source_signatures
  ADD COLUMN IF NOT EXISTS recovery_remarks TEXT;

ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_assignment_source_check;

ALTER TABLE docutracker_rsp_source_signatures
  ADD CONSTRAINT docutracker_rsp_source_signatures_assignment_source_check
  CHECK (assignment_source IN ('creator', 'automatic', 'admin_recovery', 'manual'));

ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_recovery_remarks_check;

ALTER TABLE docutracker_rsp_source_signatures
  ADD CONSTRAINT docutracker_rsp_source_signatures_recovery_remarks_check
  CHECK (
    recovery_remarks IS NULL
    OR length(btrim(recovery_remarks)) BETWEEN 5 AND 500
  );

-- Best-effort backfill: prepared_by rows that still match the form creator.
UPDATE docutracker_rsp_source_signatures s
SET assignment_source = 'creator'
FROM applicants_profile_entries f
WHERE s.source_table = 'applicants_profile_entries'
  AND s.source_record_id = f.id
  AND s.slot_key = 'prepared_by'
  AND f.created_by IS NOT NULL
  AND s.assigned_signer_id = f.created_by
  AND s.assignment_source = 'manual';

UPDATE docutracker_rsp_source_signatures s
SET assignment_source = 'creator'
FROM selection_lineup_entries f
WHERE s.source_table = 'selection_lineup_entries'
  AND s.source_record_id = f.id
  AND s.slot_key = 'prepared_by'
  AND f.created_by IS NOT NULL
  AND s.assigned_signer_id = f.created_by
  AND s.assignment_source = 'manual';

UPDATE docutracker_rsp_source_signatures s
SET assignment_source = 'creator'
FROM computation_of_points_entries f
WHERE s.source_table = 'computation_of_points_entries'
  AND s.source_record_id = f.id
  AND s.slot_key = 'prepared_by'
  AND f.created_by IS NOT NULL
  AND s.assigned_signer_id = f.created_by
  AND s.assignment_source = 'manual';

UPDATE docutracker_rsp_source_signatures s
SET assignment_source = 'creator'
FROM turn_around_time_entries f
WHERE s.source_table = 'turn_around_time_entries'
  AND s.source_record_id = f.id
  AND s.slot_key = 'prepared_by'
  AND f.created_by IS NOT NULL
  AND s.assigned_signer_id = f.created_by
  AND s.assignment_source = 'manual';

UPDATE docutracker_rsp_source_signatures s
SET assignment_source = 'creator'
FROM idp_entries f
WHERE s.source_table = 'idp_entries'
  AND s.source_record_id = f.id
  AND s.slot_key = 'prepared_by'
  AND f.created_by IS NOT NULL
  AND s.assigned_signer_id = f.created_by
  AND s.assignment_source = 'manual';

COMMIT;
