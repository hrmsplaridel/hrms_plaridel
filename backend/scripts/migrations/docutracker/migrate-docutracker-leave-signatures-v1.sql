BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_leave_signatures (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  leave_request_id UUID NOT NULL
    REFERENCES leave_requests(id) ON DELETE CASCADE,
  slot_key TEXT NOT NULL,
  assigned_signer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  signature_asset_id UUID NOT NULL
    REFERENCES docutracker_signature_assets(id) ON DELETE RESTRICT,
  signed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  signer_name_snapshot TEXT NOT NULL,
  signed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_leave_signatures_slot_check
    CHECK (slot_key = 'applicant'),
  CONSTRAINT docutracker_leave_signatures_signer_check
    CHECK (assigned_signer_id = signed_by),
  CONSTRAINT docutracker_leave_signatures_name_check
    CHECK (length(btrim(signer_name_snapshot)) BETWEEN 1 AND 200),
  CONSTRAINT docutracker_leave_signatures_request_slot_unique
    UNIQUE (leave_request_id, slot_key)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_leave_signatures_signer
  ON docutracker_leave_signatures(assigned_signer_id, leave_request_id);

COMMIT;
