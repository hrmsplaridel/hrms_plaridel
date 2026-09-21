BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_rsp_source_signatures (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  source_table TEXT NOT NULL,
  source_record_id UUID NOT NULL,
  slot_key TEXT NOT NULL,
  label TEXT NOT NULL,
  assigned_signer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  signature_asset_id UUID REFERENCES docutracker_signature_assets(id) ON DELETE RESTRICT,
  signed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  signer_name_snapshot TEXT,
  signed_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_rsp_source_signatures_source_check CHECK (
    source_table IN (
      'applicants_profile_entries',
      'selection_lineup_entries',
      'computation_of_points_entries',
      'work_experience_sheet_entries',
      'turn_around_time_entries'
    )
  ),
  CONSTRAINT docutracker_rsp_source_signatures_slot_check CHECK (
    slot_key IN ('prepared_by', 'checked_by', 'applicant', 'noted_by')
  ),
  CONSTRAINT docutracker_rsp_source_signatures_state_check CHECK (
    (signature_asset_id IS NULL AND signed_by IS NULL AND signer_name_snapshot IS NULL AND signed_at IS NULL)
    OR
    (signature_asset_id IS NOT NULL AND signed_by = assigned_signer_id
      AND length(btrim(signer_name_snapshot)) BETWEEN 1 AND 200 AND signed_at IS NOT NULL)
  ),
  CONSTRAINT docutracker_rsp_source_signatures_unique UNIQUE (
    source_table, source_record_id, slot_key
  )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_rsp_source_signatures_assignee
  ON docutracker_rsp_source_signatures(assigned_signer_id, source_table, source_record_id);

COMMIT;
