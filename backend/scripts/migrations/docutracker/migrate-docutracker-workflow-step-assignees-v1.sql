-- DocuTracker: normalize workflow steps + per-step user assignees (v1)
--
-- Creates:
--  - docutracker_workflow_steps
--  - docutracker_workflow_step_assignees
--
-- Backfills from docutracker_routing_config_versions.steps JSONB
-- using the LATEST version per document_type.
--
-- Notes:
-- - For assignee_type='user': user_ids[0] becomes PRIMARY, remaining become BACKUP rank 1..N.
-- - For other assignee types, we create the step row but do not create assignee rows (manual follow-up).

BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_workflow_steps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  workflow_version INT NOT NULL DEFAULT 1,
  step_order INT NOT NULL CHECK (step_order > 0),
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  label TEXT,
  enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_type, workflow_version, step_order)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_type_version
  ON docutracker_workflow_steps(document_type, workflow_version);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_department
  ON docutracker_workflow_steps(department_id);

CREATE TABLE IF NOT EXISTS docutracker_workflow_step_assignees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  step_id UUID NOT NULL REFERENCES docutracker_workflow_steps(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  backup_rank INT NULL CHECK (backup_rank IS NULL OR backup_rank > 0),
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  allowed_actions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (step_id, user_id),
  CHECK (NOT is_primary OR backup_rank IS NULL),
  CHECK (is_primary OR backup_rank IS NOT NULL),
  UNIQUE (step_id, backup_rank),
  CHECK (allowed_actions <@ ARRAY['approve','forward','reject','return']::TEXT[])
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_step_assignees_one_primary_per_step
  ON docutracker_workflow_step_assignees(step_id)
  WHERE is_primary = true;

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignees_user
  ON docutracker_workflow_step_assignees(user_id);

CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignees_step_enabled
  ON docutracker_workflow_step_assignees(step_id)
  WHERE is_enabled = true;

-- Backfill from latest versions table.
WITH latest AS (
  SELECT document_type, MAX(version) AS version
  FROM docutracker_routing_config_versions
  GROUP BY document_type
),
steps AS (
  SELECT
    v.document_type,
    v.version,
    s AS step_json
  FROM docutracker_routing_config_versions v
  JOIN latest l
    ON l.document_type = v.document_type
   AND l.version = v.version
  CROSS JOIN LATERAL jsonb_array_elements(v.steps) AS s
),
normalized AS (
  SELECT
    document_type,
    version,
    NULLIF((step_json->>'step_order')::int, 0) AS step_order,
    lower(trim(coalesce(step_json->>'assignee_type', ''))) AS assignee_type,
    NULLIF(step_json->>'department_id', '')::uuid AS department_id,
    NULLIF(step_json->>'label', '') AS label,
    COALESCE((step_json->>'enabled')::boolean, true) AS enabled,
    CASE
      WHEN jsonb_typeof(step_json->'user_ids') = 'array'
        THEN (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(step_json->'user_ids') AS x)
      ELSE NULL
    END AS user_ids
  FROM steps
  WHERE (step_json ? 'step_order')
)
INSERT INTO docutracker_workflow_steps (document_type, workflow_version, step_order, department_id, label, enabled)
SELECT
  n.document_type,
  n.version,
  n.step_order,
  n.department_id,
  n.label,
  n.enabled
FROM normalized n
WHERE n.step_order IS NOT NULL
ON CONFLICT (document_type, workflow_version, step_order)
DO UPDATE SET
  department_id = EXCLUDED.department_id,
  label = COALESCE(EXCLUDED.label, docutracker_workflow_steps.label),
  enabled = EXCLUDED.enabled,
  updated_at = now();

-- Insert assignees for "user" steps (primary + backups).
WITH latest AS (
  SELECT document_type, MAX(version) AS version
  FROM docutracker_routing_config_versions
  GROUP BY document_type
),
steps AS (
  SELECT
    v.document_type,
    v.version,
    s AS step_json
  FROM docutracker_routing_config_versions v
  JOIN latest l
    ON l.document_type = v.document_type
   AND l.version = v.version
  CROSS JOIN LATERAL jsonb_array_elements(v.steps) AS s
),
normalized AS (
  SELECT
    document_type,
    version,
    NULLIF((step_json->>'step_order')::int, 0) AS step_order,
    lower(trim(coalesce(step_json->>'assignee_type', ''))) AS assignee_type,
    CASE
      WHEN jsonb_typeof(step_json->'user_ids') = 'array'
        THEN (SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(step_json->'user_ids') AS x)
      ELSE NULL
    END AS user_ids
  FROM steps
  WHERE (step_json ? 'step_order')
),
user_steps AS (
  SELECT * FROM normalized
  WHERE assignee_type = 'user'
    AND step_order IS NOT NULL
    AND user_ids IS NOT NULL
    AND array_length(user_ids, 1) >= 1
),
step_ids AS (
  SELECT s.id AS step_id, u.document_type, u.version, u.step_order, u.user_ids
  FROM user_steps u
  JOIN docutracker_workflow_steps s
    ON s.document_type = u.document_type
   AND s.workflow_version = u.version
   AND s.step_order = u.step_order
)
INSERT INTO docutracker_workflow_step_assignees
  (step_id, user_id, is_primary, backup_rank, is_enabled, allowed_actions)
SELECT
  x.step_id,
  uid,
  (ord = 1) AS is_primary,
  CASE WHEN ord = 1 THEN NULL ELSE (ord - 1) END AS backup_rank,
  true AS is_enabled,
  ARRAY['approve','forward','reject','return']::TEXT[] AS allowed_actions
FROM step_ids x
CROSS JOIN LATERAL unnest(x.user_ids) WITH ORDINALITY AS t(uid, ord)
ON CONFLICT (step_id, user_id)
DO UPDATE SET
  is_primary = EXCLUDED.is_primary,
  backup_rank = EXCLUDED.backup_rank,
  is_enabled = EXCLUDED.is_enabled,
  allowed_actions = EXCLUDED.allowed_actions,
  updated_at = now();

COMMIT;

