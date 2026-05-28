-- =============================================================================
-- HRMS Plaridel — DocuTracker: INSTALL PHASE 1 (core, 01–08)
-- =============================================================================
-- PREREQUISITE: psql -d YOUR_DB -f scripts/init-schema.sql
-- Requires: uuid-ossp, users, departments (and related core HR tables).
-- NEXT (required before post-hardening phases): run docutracker-install-production-hardening-apply-once.sql
--
-- TABLE OF CONTENTS
--   01 — BASE SCHEMA (tables, indexes)
--   02 — MVP CONSTRAINTS (status checks, permissions, routing indexes)
--   03 — SUPABASE / STANDALONE PARITY (columns, nullable assignee)
--   04 — WORKFLOW VERSIONING (routing_config_versions, workflow_version on documents)
--   05 — WORKFLOW STEPS + STEP ASSIGNEES (normalized selected-person)
--   06 — STEP ASSIGNEE CONSTRAINT TRIGGER (primary + enabled rules)
--   07 — ROUTING RECORD ASSIGNEES (junction + backfill)
--   08 — HARDENING V2 (numeric guards, notifications event_key, permissions uniqueness, transition_requests)
--
-- =============================================================================



-- #############################################################################
-- 01 — BASE SCHEMA (tables, indexes)
-- Source file: init-schema-docutracker.sql
-- #############################################################################

-- HRMS Plaridel - DocuTracker Module
-- Run AFTER init-schema.sql (requires: users, departments)
-- Run: psql -d hrms_plaridel -f scripts/init-schema-docutracker.sql

-- =========================
-- DOCUTRACKER - DOCUMENTS
-- =========================
CREATE TABLE IF NOT EXISTS docutracker_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_number TEXT UNIQUE,
  document_type TEXT NOT NULL DEFAULT 'memo',
  title TEXT NOT NULL,
  description TEXT,
  -- Link back to a specific form entry from another module (LD, RSP, DTR, etc.)
  source_module TEXT,          -- e.g. 'ld', 'rsp', 'dtr'
  source_table TEXT,           -- e.g. 'bi_form_entries', 'recruitment_applications'
  source_record_id UUID,       -- id of the row in that table
  source_title TEXT,           -- optional display title from the linked form
  file_path TEXT,
  file_name TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  current_holder_id UUID REFERENCES users(id) ON DELETE SET NULL,
  current_step INT DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  escalation_level INT DEFAULT 0,
  needs_admin_intervention BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_routing_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL UNIQUE,
  steps JSONB NOT NULL DEFAULT '[]',
  review_deadline_hours INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_document_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_name TEXT,
  from_step INT,
  to_step INT,
  from_status TEXT,
  to_status TEXT,
  remarks TEXT,
  is_overdue_log BOOLEAN DEFAULT false,
  is_escalation_log BOOLEAN DEFAULT false,
  escalation_level INT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_routing_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  step_order INT NOT NULL,
  assignee_id UUID REFERENCES users(id) ON DELETE SET NULL,
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Multiple assignees per routing record (reviewers/signatories).
CREATE TABLE IF NOT EXISTS docutracker_routing_record_assignees (
  routing_record_id UUID NOT NULL REFERENCES docutracker_routing_records(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (routing_record_id, user_id)
);

CREATE TABLE IF NOT EXISTS docutracker_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL
    CHECK (type IN ('assigned', 'deadline_near', 'overdue', 'escalated', 'returned', 'rejected')),
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_permissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id TEXT,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL DEFAULT '*',
  action TEXT NOT NULL,
  granted BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_escalation_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  escalation_target_role TEXT,
  escalation_delay_minutes INT DEFAULT 60,
  max_escalation_level INT DEFAULT 3,
  notify_original_sender BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_created_by ON docutracker_documents(created_by);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_current_holder ON docutracker_documents(current_holder_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_status ON docutracker_documents(status);
CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_id ON docutracker_document_history(document_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_id ON docutracker_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_routing_record_assignees_user
  ON docutracker_routing_record_assignees(user_id);


-- #############################################################################
-- 02 — MVP CONSTRAINTS (status checks, permissions, routing indexes)
-- Source file: migrate-docutracker-mvp-constraints.sql
-- #############################################################################

-- DocuTracker MVP constraint hardening for existing databases.
-- Run after init-schema-docutracker.sql has already created tables.

-- Normalize legacy camelCase status values (if any) before constraints are tightened.
UPDATE docutracker_documents
SET status = 'in_review'
WHERE status = 'inReview';

UPDATE docutracker_routing_records
SET status = 'in_review'
WHERE status = 'inReview';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'docutracker_documents_status_check_v2'
  ) THEN
    ALTER TABLE docutracker_documents DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;
    ALTER TABLE docutracker_documents
      ADD CONSTRAINT docutracker_documents_status_check_v2
      CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'returned', 'forwarded', 'overdue', 'escalated', 'cancelled'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'docutracker_routing_records_status_check_v1'
  ) THEN
    ALTER TABLE docutracker_routing_records
      ADD CONSTRAINT docutracker_routing_records_status_check_v1
      CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'returned', 'forwarded', 'overdue', 'escalated', 'cancelled'));
  END IF;
END $$;

DO $$
BEGIN
  ALTER TABLE docutracker_permissions
    DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check;
  ALTER TABLE docutracker_permissions
    DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check_v1;
  ALTER TABLE docutracker_permissions
    ADD CONSTRAINT docutracker_permissions_action_check_v1
    CHECK (action IN ('view', 'create', 'create_draft', 'edit', 'download', 'delete', 'return', 'forward', 'approve', 'reject', 'submit'));
END $$;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_doc_type
  ON docutracker_documents(document_type);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_unique
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_routing_records_unique_step
  ON docutracker_routing_records(document_id, step_order);

ALTER TABLE docutracker_routing_records
  ALTER COLUMN assignee_id DROP NOT NULL;

ALTER TABLE docutracker_routing_records
  DROP CONSTRAINT IF EXISTS docutracker_routing_records_assignee_id_fkey;

ALTER TABLE docutracker_routing_records
  ADD CONSTRAINT docutracker_routing_records_assignee_id_fkey
  FOREIGN KEY (assignee_id) REFERENCES users(id) ON DELETE SET NULL;


-- #############################################################################
-- 03 — SUPABASE / STANDALONE PARITY (columns, nullable assignee)
-- Source file: migrate-docutracker-supabase-parity.sql
-- #############################################################################

-- Align existing PostgreSQL DocuTracker tables with standalone HRMS schema
-- (migrated from Supabase). Safe to run multiple times.
-- Run: psql -d hrms_plaridel -f scripts/migrate-docutracker-supabase-parity.sql

ALTER TABLE docutracker_document_history
  ADD COLUMN IF NOT EXISTS actor_name TEXT;

ALTER TABLE docutracker_routing_records
  ALTER COLUMN assignee_id DROP NOT NULL;

ALTER TABLE docutracker_documents DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;

-- Former Supabase RLS policies used role `authenticated` with broad access.
-- This app enforces access via Express + JWT. Optional RLS for a future
-- restricted DB role (uncomment and create role `hrms_app` if needed):
--
-- ALTER TABLE docutracker_documents ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY docutracker_documents_service ON docutracker_documents
--   FOR ALL TO hrms_app USING (true) WITH CHECK (true);


-- #############################################################################
-- 04 — WORKFLOW VERSIONING (routing_config_versions, workflow_version on documents)
-- Source file: migrate-docutracker-workflow-versioning.sql
-- #############################################################################

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


-- #############################################################################
-- 05 — WORKFLOW STEPS + STEP ASSIGNEES (normalized selected-person)
-- Source file: migrate-docutracker-workflow-step-assignees-v1.sql
-- #############################################################################

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


-- #############################################################################
-- 06 — STEP ASSIGNEE CONSTRAINT TRIGGER (primary + enabled rules)
-- Source file: migrate-docutracker-workflow-step-assignees-constraints-v1.sql
-- #############################################################################

-- DocuTracker: stronger validation for selected-person workflow assignees (constraints v1)
--
-- Enforces at COMMIT time (deferrable) that:
-- - each workflow step has at least one ENABLED assignee row
-- - exactly one ENABLED primary assignee exists per step
--
-- This complements existing UNIQUE constraints and API-level validation.

BEGIN;

-- Create a constraint trigger that checks per-step invariants.
CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  sid uuid;
  enabled_count int;
  enabled_primary_count int;
BEGIN
  sid := COALESCE(NEW.step_id, OLD.step_id);
  IF sid IS NULL THEN
    RETURN NULL;
  END IF;

  -- If the parent step has been deleted (or is being deleted), we don't need to enforce this.
  IF NOT EXISTS (SELECT 1 FROM docutracker_workflow_steps WHERE id = sid) THEN
    RETURN NULL;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE a.is_enabled = true) AS enabled_count,
    COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true) AS enabled_primary_count
  INTO enabled_count, enabled_primary_count
  FROM docutracker_workflow_step_assignees a
  WHERE a.step_id = sid;

  IF enabled_count < 1 THEN
    RAISE EXCEPTION 'Workflow step % must have at least one enabled assignee', sid
      USING ERRCODE = '23514';
  END IF;

  IF enabled_primary_count <> 1 THEN
    RAISE EXCEPTION 'Workflow step % must have exactly one enabled primary assignee', sid
      USING ERRCODE = '23514';
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_docutracker_step_assignees_invariants ON docutracker_workflow_step_assignees;

CREATE CONSTRAINT TRIGGER trg_docutracker_step_assignees_invariants
AFTER INSERT OR UPDATE OR DELETE
ON docutracker_workflow_step_assignees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE PROCEDURE docutracker_enforce_step_assignees_invariants();

COMMIT;


-- #############################################################################
-- 07 — ROUTING RECORD ASSIGNEES (junction + backfill)
-- Source file: migrate-docutracker-routing-record-assignees-v1.sql
-- #############################################################################

-- DocuTracker: allow multiple assignees per routing step (v1)
--
-- Adds a join table so a workflow step can have multiple assigned reviewers/signatories.
-- Backfills existing rows from docutracker_routing_records.assignee_id.

BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_routing_record_assignees (
  routing_record_id UUID NOT NULL REFERENCES docutracker_routing_records(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (routing_record_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_record_assignees_user
  ON docutracker_routing_record_assignees(user_id);

-- Backfill from legacy single-assignee column.
INSERT INTO docutracker_routing_record_assignees (routing_record_id, user_id)
SELECT rr.id, rr.assignee_id
FROM docutracker_routing_records rr
WHERE rr.assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

COMMIT;


-- #############################################################################
-- 08 — HARDENING V2 (numeric guards, notifications event_key, permissions uniqueness, transition_requests)
-- Source file: migrate-docutracker-hardening-v2.sql
-- #############################################################################

-- DocuTracker hardening v2
-- Safe to run repeatedly.

-- 1) Routing / escalation numeric guards
ALTER TABLE docutracker_routing_configs
  DROP CONSTRAINT IF EXISTS docutracker_routing_configs_review_deadline_hours_check;
ALTER TABLE docutracker_routing_configs
  ADD CONSTRAINT docutracker_routing_configs_review_deadline_hours_check
  CHECK (review_deadline_hours > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_escalation_delay_minutes_check;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_escalation_delay_minutes_check
  CHECK (escalation_delay_minutes > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_max_escalation_level_check;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_max_escalation_level_check
  CHECK (max_escalation_level >= 1);

-- 2) Notification event key for deterministic idempotency
ALTER TABLE docutracker_notifications
  ADD COLUMN IF NOT EXISTS event_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_notifications_event_key_unique
  ON docutracker_notifications(document_id, user_id, type, event_key)
  WHERE event_key IS NOT NULL;

-- 3) Permission row hygiene and uniqueness
DELETE FROM docutracker_permissions
WHERE user_id IS NULL
  AND role_id IS NULL;

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY user_id, role_id, document_type, action
           ORDER BY updated_at DESC NULLS LAST, created_at DESC, id DESC
         ) AS rn
  FROM docutracker_permissions
)
DELETE FROM docutracker_permissions p
USING ranked r
WHERE p.id = r.id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_user_unique
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_role_unique
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;

ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_scope_check_v1;
ALTER TABLE docutracker_permissions
  ADD CONSTRAINT docutracker_permissions_scope_check_v1
  CHECK ((user_id IS NOT NULL) <> (role_id IS NOT NULL));

-- 4) Query-performance indexes for list/history access patterns
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_type_status_created
  ON docutracker_documents(document_type, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_holder_status_deadline
  ON docutracker_documents(current_holder_id, status, deadline_time);

CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_created_desc
  ON docutracker_document_history(document_id, created_at DESC);

-- 5) Transition idempotency storage
CREATE TABLE IF NOT EXISTS docutracker_transition_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  response_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (document_id, action, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_transition_requests_lookup
  ON docutracker_transition_requests(document_id, action, idempotency_key);
