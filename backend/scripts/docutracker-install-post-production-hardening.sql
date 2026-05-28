-- =============================================================================
-- HRMS Plaridel — DocuTracker: INSTALL PHASE 3 (post production hardening, 10–13)
-- =============================================================================
-- PREREQUISITE: phase 1 complete AND docutracker-install-production-hardening-apply-once.sql applied.
-- Section 10 drops/replaces *_prod_v1 status constraints created in production hardening.
-- Section 11 fails if multiple active routing rows exist per document; fix data then re-run.
-- Section 13 raises if optional source-module tables are missing; comment it out for DocuTracker-only DBs.
--
-- TABLE OF CONTENTS
--   10 — STATUS SEMANTICS V2 (drop forwarded as document status)
--   11 — ACTIVE ROUTING STEP INDEX (one active row per document)
--   12 — SEED PERMISSION BASELINE (role rows)
--   13 — OPTIONAL VERIFY (checks source tables exist)
--   14 — AI SUMMARIES (saved metadata-only summaries)
--
-- =============================================================================



-- #############################################################################
-- 10 — STATUS SEMANTICS V2 (drop forwarded as document status)
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
-- 11 — ACTIVE ROUTING STEP INDEX (one active row per document)
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
-- 12 — SEED PERMISSION BASELINE (role rows)
-- Source file: seed-docutracker-permission-baseline.sql
-- #############################################################################

-- DocuTracker permission baseline seed/upsert
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/seed-docutracker-permission-baseline.sql
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
-- 13 — OPTIONAL VERIFY (checks source tables exist)
-- Source file: verify-docutracker-source-parity.sql
-- #############################################################################

-- DocuTracker source-schema parity verifier
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/verify-docutracker-source-parity.sql
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
-- 14 — AI SUMMARIES (saved metadata-only summaries)
-- Source file: migrate-docutracker-ai-summaries-v1.sql
-- #############################################################################

-- DocuTracker AI summaries v1.
-- Stores generated summaries separately from workflow/runtime document state.

CREATE TABLE IF NOT EXISTS docutracker_ai_summaries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  generated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  provider TEXT NOT NULL DEFAULT 'ollama',
  model TEXT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_docutracker_ai_summaries_document_generated
  ON docutracker_ai_summaries(document_id, generated_at DESC);
