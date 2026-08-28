-- =============================================================================
-- HRMS Plaridel - DocuTracker: INSTALL PHASE 3 (post production hardening, 10-16)
-- =============================================================================
-- PREREQUISITE: phase 1 complete AND docutracker-install-production-hardening-apply-once.sql applied.
-- Section 10 drops/replaces *_prod_v1 status constraints created in production hardening.
-- Section 11 fails if multiple active routing rows exist per document; fix data then re-run.
-- Section 13 raises if optional source-module tables are missing; comment it out for DocuTracker-only DBs.
-- Section 14 is additive and keeps existing app-facing table/column names stable.
-- Section 15 allows configuration steps with zero assignees while preserving assigned-step invariants.
-- Section 16 adds A4 document content and server-locked e-signature persistence.
--
-- TABLE OF CONTENTS
--   10 - STATUS SEMANTICS V2 (drop forwarded as document status)
--   11 - ACTIVE ROUTING STEP INDEX (one active row per document)
--   12 - SEED PERMISSION BASELINE (role rows)
--   13 - OPTIONAL VERIFY (checks source tables exist)
--   14 - SAFE SCHEMA IMPROVEMENTS (metadata, files, notifications)
--   15 - ALLOW UNASSIGNED WORKFLOW STEPS
--   16 - DOCUMENT BUILDER + E-SIGNATURES
--
-- =============================================================================



-- #############################################################################
-- 10 - STATUS SEMANTICS V2 (drop forwarded as document status)
-- Source file: migrate-docutracker-status-semantics-v2.sql
-- #############################################################################

-- DocuTracker: status semantics v2 (remove 'forwarded' as a status)
-- Date: 2026-04-16
--
-- Goal:
-- - Standardize "active" workflow state to 'in_review'
-- - Keep 'forwarded' as a HISTORY action only (not a document/routing status)
--
-- This migration:
-- 1) Normalizes existing 'forwarded' rows to 'in_review'
-- 2) Replaces prior status CHECK constraints with a single prod_v2 rule (no 'forwarded')

-- ============================================================
-- 1) DATA NORMALIZATION
-- ============================================================
UPDATE docutracker_documents
SET status = 'in_review'
WHERE status = 'forwarded';

UPDATE docutracker_routing_records
SET status = 'in_review'
WHERE status = 'forwarded';

-- ============================================================
-- 2) CHECK CONSTRAINTS (idempotent across MVP / prod_v1 / re-runs)
-- ============================================================
-- Drop every known name so ADD CONSTRAINT ... prod_v2 never collides with an
-- older CHECK that still allows 'forwarded' (would make prod_v2 redundant or fail).
DO $$
BEGIN
  -- Documents — known historical names from init-schema, MVP, production hardening, and this migration
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_v2;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_prod_v1;
  ALTER TABLE docutracker_documents
    DROP CONSTRAINT IF EXISTS docutracker_documents_status_check_prod_v2;

  ALTER TABLE docutracker_documents
    ADD CONSTRAINT docutracker_documents_status_check_prod_v2
    CHECK (status IN (
      'pending',
      'in_review',
      'approved',
      'rejected',
      'returned',
      'overdue',
      'escalated',
      'cancelled'
    ));

  -- Routing records
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_v1;
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_prod_v1;
  ALTER TABLE docutracker_routing_records
    DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_prod_v2;

  ALTER TABLE docutracker_routing_records
    ADD CONSTRAINT docutracker_routing_records_status_check_prod_v2
    CHECK (status IN (
      'pending',
      'in_review',
      'approved',
      'rejected',
      'returned',
      'overdue',
      'escalated',
      'cancelled'
    ));
END $$;


-- #############################################################################
-- 11 - ACTIVE ROUTING STEP INDEX (one active row per document)
-- Source file: migrate-docutracker-active-step-index-v1.sql
-- #############################################################################

-- DocuTracker: widen "one active routing record" enforcement
-- Date: 2026-04-16
--
-- Goal:
-- Ensure that a document cannot have multiple simultaneously-active routing records,
-- including cases where escalation marks a routing record as 'escalated'.
--
-- Notes:
-- - This is safe to run after migrate-docutracker-production-hardening-apply-once.sql
-- - If it fails, you have existing data with multiple active routing rows per document.
--   Fix the data (keep only one active row per document) then re-run.

DO $$
BEGIN
  -- Drop the older partial unique index if present so we can replace it.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'idx_docutracker_routing_records_one_active_per_doc'
  ) THEN
    EXECUTE 'DROP INDEX idx_docutracker_routing_records_one_active_per_doc';
  END IF;

  BEGIN
    CREATE UNIQUE INDEX idx_docutracker_routing_records_one_active_per_doc
      ON docutracker_routing_records(document_id)
      WHERE status IN ('pending', 'in_review', 'escalated', 'overdue');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION
      'Cannot enforce one-active-step constraint (v1): existing data has multiple active routing_records per document. Fix data then re-run.';
  END;
END $$;


-- #############################################################################
-- 12 - SEED PERMISSION BASELINE (role rows)
-- Source file: seed-docutracker-permission-baseline.sql
-- #############################################################################

-- DocuTracker permission baseline seed/upsert
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/migrations/docutracker/seed-docutracker-permission-baseline.sql
--
-- Notes:
-- - This script defines baseline ROLE permissions using document_type='*'.
-- - Explicit user-level permissions in the UI can still override these.
-- - role_id values must exist in docutracker_roles (see production hardening).
--   Legacy JWT aliases (hr_staff, dept_head) are mapped in app/SQL via docutracker_role_aliases;
--   do not insert non-canonical role_id rows here or the role FK will reject them.

WITH baseline(role_id, document_type, action, granted) AS (
  VALUES
    -- Employee baseline: can create/submit/view/download their workflow-relevant docs.
    ('employee',  '*', 'view',     true),
    ('employee',  '*', 'create',   true),
    ('employee',  '*', 'submit',   true),
    ('employee',  '*', 'download', true),
    ('employee',  '*', 'edit',     false),
    ('employee',  '*', 'delete',   false),
    ('employee',  '*', 'forward',  false),
    ('employee',  '*', 'approve',  false),
    ('employee',  '*', 'reject',   false),
    ('employee',  '*', 'return',   false),

    -- HR baseline: review-capable.
    ('hr',        '*', 'view',     true),
    ('hr',        '*', 'create',   true),
    ('hr',        '*', 'submit',   true),
    ('hr',        '*', 'download', true),
    ('hr',        '*', 'edit',     true),
    ('hr',        '*', 'delete',   false),
    ('hr',        '*', 'forward',  true),
    ('hr',        '*', 'approve',  true),
    ('hr',        '*', 'reject',   true),
    ('hr',        '*', 'return',   true),

    -- Supervisor baseline: review-capable.
    ('supervisor','*', 'view',     true),
    ('supervisor','*', 'create',   true),
    ('supervisor','*', 'submit',   true),
    ('supervisor','*', 'download', true),
    ('supervisor','*', 'edit',     true),
    ('supervisor','*', 'delete',   false),
    ('supervisor','*', 'forward',  true),
    ('supervisor','*', 'approve',  true),
    ('supervisor','*', 'reject',   true),
    ('supervisor','*', 'return',   true),

    -- Admin explicit baseline (admin already has service-level override).
    ('admin',     '*', 'view',     true),
    ('admin',     '*', 'create',   true),
    ('admin',     '*', 'submit',   true),
    ('admin',     '*', 'download', true),
    ('admin',     '*', 'edit',     true),
    ('admin',     '*', 'delete',   true),
    ('admin',     '*', 'forward',  true),
    ('admin',     '*', 'approve',  true),
    ('admin',     '*', 'reject',   true),
    ('admin',     '*', 'return',   true)
)
INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
SELECT
  b.role_id,
  NULL::uuid,
  b.document_type,
  b.action,
  b.granted
FROM baseline b
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();

-- Evidence summary
SELECT
  role_id,
  action,
  document_type,
  granted
FROM docutracker_permissions
WHERE user_id IS NULL
  AND role_id IN ('employee', 'hr', 'supervisor', 'admin')
ORDER BY role_id, document_type, action;


-- #############################################################################
-- 13 - OPTIONAL VERIFY (checks source tables exist)
-- Source file: verify-docutracker-source-parity.sql
-- #############################################################################

-- DocuTracker source-schema parity verifier
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/migrations/docutracker/verify-docutracker-source-parity.sql
--
-- Purpose:
--   Fail fast if DocuTracker required source/core tables are missing.
--   This should be part of pre-release validation.

DO $$
DECLARE
  missing_tables text[];
BEGIN
  SELECT ARRAY(
    SELECT t.required_table
    FROM (
      VALUES
        -- Source module tables consumed by DocuTracker source feed
        ('public.training_daily_reports'),
        ('public.leave_requests'),
        ('public.dtr_corrections'),
        ('public.overtime_requests'),
        ('public.recruitment_applications'),
        -- DocuTracker core tables
        ('public.docutracker_documents'),
        ('public.docutracker_permissions'),
        ('public.docutracker_routing_configs'),
        ('public.docutracker_routing_records'),
        ('public.docutracker_document_history'),
        ('public.docutracker_notifications')
    ) AS t(required_table)
    WHERE to_regclass(t.required_table) IS NULL
  ) INTO missing_tables;

  IF array_length(missing_tables, 1) IS NOT NULL THEN
    RAISE EXCEPTION
      'DocuTracker schema parity check failed. Missing tables: %',
      array_to_string(missing_tables, ', ');
  END IF;

  RAISE NOTICE 'DocuTracker schema parity check passed. All required tables are present.';
END $$;


-- #############################################################################
-- 14 - SAFE SCHEMA IMPROVEMENTS (metadata, files, notifications)
-- Source file: migrate-docutracker-safe-improvements-v1.sql
-- #############################################################################

-- DocuTracker safe schema improvements v1.
--
-- Purpose:
-- Add richer metadata, file/version support, document type cataloging,
-- notification delivery metadata and type-aware
-- document number counters without renaming existing runtime columns.
--
-- Safe to run repeatedly after the DocuTracker production/post-hardening scripts.

BEGIN;

CREATE OR REPLACE FUNCTION docutracker_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 1) Document type catalog
-- ============================================================
CREATE TABLE IF NOT EXISTS docutracker_document_types (
  document_type TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  description TEXT,
  number_prefix TEXT,
  default_priority TEXT NOT NULL DEFAULT 'normal',
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_document_types_type_not_blank
    CHECK (btrim(document_type) <> ''),
  CONSTRAINT docutracker_document_types_display_name_not_blank
    CHECK (btrim(display_name) <> ''),
  CONSTRAINT docutracker_document_types_priority_check
    CHECK (default_priority IN ('low', 'normal', 'high', 'urgent'))
);

INSERT INTO docutracker_document_types (
  document_type,
  display_name,
  description,
  number_prefix
)
VALUES
  ('memo', 'Memo', 'Internal memorandum document', 'MEMO'),
  ('purchaseRequest', 'Purchase Request', 'Purchase request document', 'PR')
ON CONFLICT (document_type) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = COALESCE(docutracker_document_types.description, EXCLUDED.description),
  number_prefix = COALESCE(docutracker_document_types.number_prefix, EXCLUDED.number_prefix),
  updated_at = now();

WITH discovered(document_type) AS (
  SELECT DISTINCT document_type
  FROM docutracker_documents
  WHERE document_type IS NOT NULL AND btrim(document_type) <> ''
  UNION
  SELECT DISTINCT document_type
  FROM docutracker_routing_configs
  WHERE document_type IS NOT NULL AND btrim(document_type) <> ''
  UNION
  SELECT DISTINCT document_type
  FROM docutracker_routing_config_versions
  WHERE document_type IS NOT NULL AND btrim(document_type) <> ''
  UNION
  SELECT DISTINCT document_type
  FROM docutracker_permissions
  WHERE document_type IS NOT NULL AND btrim(document_type) <> '' AND document_type <> '*'
)
INSERT INTO docutracker_document_types (document_type, display_name, number_prefix)
SELECT
  d.document_type,
  d.document_type,
  upper(left(regexp_replace(d.document_type, '[^A-Za-z0-9]+', '', 'g'), 8))
FROM discovered d
ON CONFLICT (document_type) DO NOTHING;

DROP TRIGGER IF EXISTS trg_docutracker_document_types_updated_at ON docutracker_document_types;
CREATE TRIGGER trg_docutracker_document_types_updated_at
BEFORE UPDATE ON docutracker_document_types
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

-- ============================================================
-- 2) Document metadata, soft lifecycle markers, and query indexes
-- ============================================================
ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS confidentiality_level TEXT NOT NULL DEFAULT 'internal',
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_priority_check_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_priority_check_v1
  CHECK (priority IN ('low', 'normal', 'high', 'urgent'));

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_confidentiality_check_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_confidentiality_check_v1
  CHECK (confidentiality_level IN ('public', 'internal', 'confidential', 'restricted'));

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_metadata_object_check_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_metadata_object_check_v1
  CHECK (jsonb_typeof(metadata) = 'object');

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_priority_status
  ON docutracker_documents(priority, status, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_source_record
  ON docutracker_documents(source_module, source_table, source_record_id)
  WHERE source_record_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_metadata_gin
  ON docutracker_documents USING GIN (metadata);

-- ============================================================
-- 3) Multiple document files / attachment versions
-- ============================================================
CREATE TABLE IF NOT EXISTS docutracker_document_files (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  mime_type TEXT,
  file_size BIGINT,
  checksum TEXT,
  version INT NOT NULL DEFAULT 1,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  is_current BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_document_files_name_not_blank
    CHECK (btrim(file_name) <> ''),
  CONSTRAINT docutracker_document_files_path_not_blank
    CHECK (btrim(file_path) <> ''),
  CONSTRAINT docutracker_document_files_size_check
    CHECK (file_size IS NULL OR file_size >= 0),
  CONSTRAINT docutracker_document_files_version_check
    CHECK (version > 0),
  UNIQUE (document_id, file_name, version)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_document_files_document
  ON docutracker_document_files(document_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_document_files_one_current
  ON docutracker_document_files(document_id, file_name)
  WHERE is_current = true;

INSERT INTO docutracker_document_files (
  document_id,
  file_name,
  file_path,
  uploaded_by,
  is_current
)
SELECT
  d.id,
  d.file_name,
  d.file_path,
  d.created_by,
  true
FROM docutracker_documents d
WHERE d.file_path IS NOT NULL
  AND btrim(d.file_path) <> ''
  AND d.file_name IS NOT NULL
  AND btrim(d.file_name) <> ''
ON CONFLICT (document_id, file_name, version) DO NOTHING;

-- ============================================================
-- 4) Notification delivery/read metadata
-- ============================================================
ALTER TABLE docutracker_notifications
  ADD COLUMN IF NOT EXISTS channel TEXT NOT NULL DEFAULT 'in_app',
  ADD COLUMN IF NOT EXISTS delivery_status TEXT NOT NULL DEFAULT 'sent',
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failure_reason TEXT;

UPDATE docutracker_notifications
SET read_at = COALESCE(read_at, created_at)
WHERE read = true
  AND read_at IS NULL;

ALTER TABLE docutracker_notifications
  DROP CONSTRAINT IF EXISTS docutracker_notifications_channel_check_v1;
ALTER TABLE docutracker_notifications
  ADD CONSTRAINT docutracker_notifications_channel_check_v1
  CHECK (channel IN ('in_app', 'email', 'sms', 'push'));

ALTER TABLE docutracker_notifications
  DROP CONSTRAINT IF EXISTS docutracker_notifications_delivery_status_check_v1;
ALTER TABLE docutracker_notifications
  ADD CONSTRAINT docutracker_notifications_delivery_status_check_v1
  CHECK (delivery_status IN ('pending', 'sent', 'delivered', 'failed', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_unread_created
  ON docutracker_notifications(user_id, created_at DESC)
  WHERE read = false;

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_delivery_pending
  ON docutracker_notifications(delivery_status, created_at)
  WHERE delivery_status IN ('pending', 'failed');

-- ============================================================
-- 5) Type-aware document number counters for future use
-- ============================================================
CREATE TABLE IF NOT EXISTS docutracker_document_number_sequences (
  year INT NOT NULL,
  document_type TEXT NOT NULL DEFAULT '*',
  scope_type TEXT NOT NULL DEFAULT 'global',
  scope_id UUID,
  prefix TEXT,
  last_value BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_number_sequences_year_check_v1
    CHECK (year BETWEEN 2000 AND 9999),
  CONSTRAINT docutracker_number_sequences_last_value_check_v1
    CHECK (last_value >= 0),
  CONSTRAINT docutracker_number_sequences_scope_check_v1
    CHECK (
      (scope_type = 'global' AND scope_id IS NULL)
      OR
      (scope_type IN ('department', 'office', 'campus') AND scope_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_number_sequences_unique
  ON docutracker_document_number_sequences (
    year,
    document_type,
    scope_type,
    COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

UPDATE docutracker_document_number_sequences ns
SET
  last_value = GREATEST(ns.last_value, s.last_value),
  updated_at = now()
FROM docutracker_document_number_seq s
WHERE ns.year = s.year
  AND ns.document_type = '*'
  AND ns.scope_type = 'global'
  AND ns.scope_id IS NULL;

INSERT INTO docutracker_document_number_sequences (
  year,
  document_type,
  scope_type,
  scope_id,
  prefix,
  last_value,
  updated_at
)
SELECT
  s.year,
  '*',
  'global',
  NULL::uuid,
  'DOC',
  s.last_value,
  now()
FROM docutracker_document_number_seq s
WHERE NOT EXISTS (
  SELECT 1
  FROM docutracker_document_number_sequences ns
  WHERE ns.year = s.year
    AND ns.document_type = '*'
    AND ns.scope_type = 'global'
    AND ns.scope_id IS NULL
);

COMMIT;


-- #############################################################################
-- 15 - ALLOW UNASSIGNED WORKFLOW STEPS
-- Source file: migrate-docutracker-allow-unassigned-workflow-steps-v2.sql
-- #############################################################################

-- DocuTracker: allow workflow steps to remain unassigned during configuration.
--
-- Existing assigned steps still require at least one enabled assignee and
-- exactly one enabled primary assignee. Workflow execution remains responsible
-- for rejecting a transition into a step that has no valid assignee.

BEGIN;

CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  sid uuid;
  assignee_count int;
  enabled_count int;
  enabled_primary_count int;
BEGIN
  sid := COALESCE(NEW.step_id, OLD.step_id);
  IF sid IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM docutracker_workflow_steps WHERE id = sid) THEN
    RETURN NULL;
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE a.is_enabled = true),
    COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true)
  INTO assignee_count, enabled_count, enabled_primary_count
  FROM docutracker_workflow_step_assignees a
  WHERE a.step_id = sid;

  IF assignee_count = 0 THEN
    RETURN NULL;
  END IF;

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

COMMIT;


-- #############################################################################
-- 16 - DOCUMENT BUILDER + E-SIGNATURES
-- Source file: migrate-docutracker-document-builder-esign-v1.sql
-- #############################################################################

-- DocuTracker document builder and e-signature persistence.
-- Apply after the DocuTracker core and workflow migrations.

BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_document_contents (
  document_id UUID PRIMARY KEY
    REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  format_version INT NOT NULL DEFAULT 1,
  pages JSONB NOT NULL DEFAULT '[]'::jsonb,
  page_size TEXT NOT NULL DEFAULT 'A4',
  margins JSONB NOT NULL DEFAULT
    '{"top":0.08,"right":0.08,"bottom":0.08,"left":0.08}'::jsonb,
  revision INT NOT NULL DEFAULT 1,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_document_contents_pages_array_check
    CHECK (jsonb_typeof(pages) = 'array'),
  CONSTRAINT docutracker_document_contents_margins_object_check
    CHECK (jsonb_typeof(margins) = 'object'),
  CONSTRAINT docutracker_document_contents_format_version_check
    CHECK (format_version > 0),
  CONSTRAINT docutracker_document_contents_revision_check
    CHECK (revision > 0),
  CONSTRAINT docutracker_document_contents_page_size_check
    CHECK (page_size = 'A4')
);

CREATE TABLE IF NOT EXISTS docutracker_signature_assets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_bytes BYTEA NOT NULL,
  mime_type TEXT NOT NULL,
  source_type TEXT NOT NULL,
  display_name TEXT,
  is_saved BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_signature_assets_mime_check
    CHECK (mime_type IN ('image/png', 'image/jpeg')),
  CONSTRAINT docutracker_signature_assets_source_check
    CHECK (source_type IN ('drawn', 'uploaded')),
  CONSTRAINT docutracker_signature_assets_size_check
    CHECK (octet_length(image_bytes) BETWEEN 1 AND 2097152)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_assets_owner_saved
  ON docutracker_signature_assets(owner_user_id, is_saved, created_at DESC);

CREATE TABLE IF NOT EXISTS docutracker_signature_fields (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL
    REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  page_number INT NOT NULL,
  position_x DOUBLE PRECISION NOT NULL,
  position_y DOUBLE PRECISION NOT NULL,
  width DOUBLE PRECISION NOT NULL,
  height DOUBLE PRECISION NOT NULL,
  assigned_signer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  label TEXT NOT NULL DEFAULT 'Sign Here',
  signature_asset_id UUID REFERENCES docutracker_signature_assets(id) ON DELETE RESTRICT,
  signed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  signer_name_snapshot TEXT,
  signed_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_signature_fields_page_check
    CHECK (page_number > 0),
  CONSTRAINT docutracker_signature_fields_position_x_check
    CHECK (position_x >= 0 AND position_x <= 1),
  CONSTRAINT docutracker_signature_fields_position_y_check
    CHECK (position_y >= 0 AND position_y <= 1),
  CONSTRAINT docutracker_signature_fields_width_check
    CHECK (width > 0 AND width <= 1 AND position_x + width <= 1),
  CONSTRAINT docutracker_signature_fields_height_check
    CHECK (height > 0 AND height <= 1 AND position_y + height <= 1),
  CONSTRAINT docutracker_signature_fields_label_check
    CHECK (length(btrim(label)) BETWEEN 1 AND 80),
  CONSTRAINT docutracker_signature_fields_signed_state_check CHECK (
    (signature_asset_id IS NULL AND signed_by IS NULL AND signed_at IS NULL
      AND locked_at IS NULL AND signer_name_snapshot IS NULL)
    OR
    (signature_asset_id IS NOT NULL AND signed_by IS NOT NULL AND signed_at IS NOT NULL
      AND locked_at IS NOT NULL AND signer_name_snapshot IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_fields_document_page
  ON docutracker_signature_fields(document_id, page_number, created_at);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_fields_signer_pending
  ON docutracker_signature_fields(assigned_signer_id, document_id)
  WHERE signed_at IS NULL;

COMMIT;
