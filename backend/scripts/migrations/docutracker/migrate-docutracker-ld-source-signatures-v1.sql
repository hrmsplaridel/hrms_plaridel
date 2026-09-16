BEGIN;

-- The table name is retained for backward compatibility. It is owned by
-- DocuTracker and now stores fixed signature slots for allowlisted RSP and
-- L&D source forms; source-module tables remain unchanged.
ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_source_check;

ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_source_table_check;

ALTER TABLE docutracker_rsp_source_signatures
  ADD CONSTRAINT docutracker_rsp_source_signatures_source_check CHECK (
    source_table IN (
      'applicants_profile_entries',
      'selection_lineup_entries',
      'computation_of_points_entries',
      'work_experience_sheet_entries',
      'turn_around_time_entries',
      'idp_entries',
      'action_brainstorming_coaching_entries'
    )
  );

ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_slot_check;

ALTER TABLE docutracker_rsp_source_signatures
  DROP CONSTRAINT IF EXISTS docutracker_rsp_source_signatures_slot_key_check;

ALTER TABLE docutracker_rsp_source_signatures
  ADD CONSTRAINT docutracker_rsp_source_signatures_slot_check CHECK (
    slot_key IN (
      'prepared_by',
      'checked_by',
      'applicant',
      'noted_by',
      'reviewed_by',
      'approved_by',
      'certified_by'
    )
  );

COMMIT;
