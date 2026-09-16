-- DocuTracker governance audit trail (apply once).
CREATE TABLE IF NOT EXISTS docutracker_governance_audit (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID NOT NULL REFERENCES users(id),
  event_type TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NULL,
  document_type TEXT NULL,
  workflow_version INT NULL,
  target_user_id UUID NULL REFERENCES users(id),
  target_role_id TEXT NULL,
  before_state JSONB NULL,
  after_state JSONB NULL,
  reason TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_docutracker_governance_audit_created_at
  ON docutracker_governance_audit(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_docutracker_governance_audit_document_type
  ON docutracker_governance_audit(document_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_docutracker_governance_audit_event_type
  ON docutracker_governance_audit(event_type, created_at DESC);
