-- Shared DocuTracker-shaped steps; published/request versions remain unchanged.
BEGIN;
ALTER TABLE approval_workflow_versions DROP CONSTRAINT IF EXISTS approval_workflow_versions_steps_check;
ALTER TABLE approval_workflow_versions ADD CONSTRAINT approval_workflow_versions_steps_check
  CHECK(jsonb_typeof(steps)='array' AND jsonb_array_length(steps) BETWEEN 1 AND 20);
ALTER TABLE docutracker_workflow_steps DROP CONSTRAINT IF EXISTS docutracker_workflow_steps_assignee_source_check;
ALTER TABLE docutracker_workflow_steps ADD CONSTRAINT docutracker_workflow_steps_assignee_source_check
  CHECK(assignee_source IN ('specific_users','department_reviewers','submitter_department_reviewers','final_hr_reviewers','active_mayor'));
ALTER TABLE docutracker_routing_config_versions ADD COLUMN IF NOT EXISTS shared_workflow_id UUID REFERENCES approval_workflows(id);
ALTER TABLE docutracker_routing_config_versions ADD COLUMN IF NOT EXISTS shared_workflow_version INTEGER;
CREATE TABLE IF NOT EXISTS approval_workflow_document_types (
  document_type TEXT PRIMARY KEY REFERENCES docutracker_document_types(document_type),
  workflow_id UUID NOT NULL REFERENCES approval_workflows(id),
  workflow_version INTEGER NOT NULL,
  docutracker_version INTEGER NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  FOREIGN KEY(workflow_id,workflow_version) REFERENCES approval_workflow_versions(workflow_id,version),
  FOREIGN KEY(document_type,docutracker_version) REFERENCES docutracker_routing_config_versions(document_type,version)
);
COMMIT;
