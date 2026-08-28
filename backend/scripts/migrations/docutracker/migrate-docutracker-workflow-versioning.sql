-- DocuTracker workflow versioning (safe editing for in-progress documents)
-- Apply once.

BEGIN;

-- 1) Add workflow_version to documents (the workflow config version used for routing).
ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS workflow_version INT;

-- 2) Create a versions table that stores immutable workflow configs per type+version.
CREATE TABLE IF NOT EXISTS docutracker_routing_config_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  version INT NOT NULL,
  steps JSONB NOT NULL,
  review_deadline_hours INT NOT NULL DEFAULT 1,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_type, version)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_config_versions_type_version_desc
  ON docutracker_routing_config_versions(document_type, version DESC);

-- 3) Backfill version table from current docutracker_routing_configs if empty.
--    Use version=1 for each document_type that doesn't have a version row yet.
INSERT INTO docutracker_routing_config_versions (document_type, version, steps, review_deadline_hours)
SELECT c.document_type, 1, c.steps, COALESCE(c.review_deadline_hours, 1)
FROM docutracker_routing_configs c
WHERE NOT EXISTS (
  SELECT 1
  FROM docutracker_routing_config_versions v
  WHERE v.document_type = c.document_type
);

-- 4) Backfill workflow_version on existing documents.
--    For safety we assign them to the highest version that exists for their type.
WITH latest AS (
  SELECT document_type, MAX(version) AS v
  FROM docutracker_routing_config_versions
  GROUP BY document_type
)
UPDATE docutracker_documents d
SET workflow_version = l.v
FROM latest l
WHERE d.document_type = l.document_type
  AND (d.workflow_version IS NULL OR d.workflow_version < 1);

COMMIT;

