-- DocuTracker production hardening (apply-once, labeled sections)
-- Date: 2026-04-16
--
-- Goal: tighten integrity + performance while remaining compatible with the
--       existing MVP scripts and data.
--
-- Notes:
-- - This script is written to be re-runnable where practical (IF EXISTS guards),
--   but you should treat it as an apply-once migration for clarity.
-- - If any section fails, fix the data issue it reports, then re-run.

-- ============================================================
-- SECTION 0) PREREQUISITES
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- SECTION 1) NORMALIZE LEGACY VALUES (safe data fixes)
-- ============================================================
-- Normalize legacy camelCase values so constraints don't fail later.
UPDATE docutracker_documents
SET status = 'in_review'
WHERE status = 'inReview';

UPDATE docutracker_routing_records
SET status = 'in_review'
WHERE status = 'inReview';

-- Normalize legacy role ids. Core install already created a partial unique index on
-- (role_id, document_type, action); updating hr_staff -> hr can duplicate an existing
-- 'hr' row and fail. Drop alias rows when the canonical baseline row already exists.
DELETE FROM docutracker_permissions p
WHERE p.user_id IS NULL
  AND p.role_id = 'hr_staff'
  AND EXISTS (
    SELECT 1 FROM docutracker_permissions c
    WHERE c.user_id IS NULL
      AND c.role_id = 'hr'
      AND c.document_type = p.document_type
      AND c.action = p.action
  );

DELETE FROM docutracker_permissions p
WHERE p.user_id IS NULL
  AND p.role_id = 'dept_head'
  AND EXISTS (
    SELECT 1 FROM docutracker_permissions c
    WHERE c.user_id IS NULL
      AND c.role_id = 'supervisor'
      AND c.document_type = p.document_type
      AND c.action = p.action
  );

UPDATE docutracker_permissions
SET role_id = 'hr'
WHERE role_id = 'hr_staff';

UPDATE docutracker_permissions
SET role_id = 'supervisor'
WHERE role_id = 'dept_head';

-- ============================================================
-- SECTION 2) STRICT CHECK CONSTRAINTS (status/action/config hygiene)
-- ============================================================
DO $$
BEGIN
  -- Document statuses (keep list aligned with app + existing migrations)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'docutracker_documents_status_check_prod_v1'
  ) THEN
    ALTER TABLE docutracker_documents
      DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;
    ALTER TABLE docutracker_documents
      ADD CONSTRAINT docutracker_documents_status_check_prod_v1
      CHECK (status IN (
        'pending',
        'in_review',
        'approved',
        'rejected',
        'returned',
        'forwarded',
        'overdue',
        'escalated',
        'cancelled'
      ));
  END IF;

  -- Routing record statuses
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'docutracker_routing_records_status_check_prod_v1'
  ) THEN
    ALTER TABLE docutracker_routing_records
      DROP CONSTRAINT IF EXISTS docutracker_routing_records_status_check_v1;
    ALTER TABLE docutracker_routing_records
      ADD CONSTRAINT docutracker_routing_records_status_check_prod_v1
      CHECK (status IN (
        'pending',
        'in_review',
        'approved',
        'rejected',
        'returned',
        'forwarded',
        'overdue',
        'escalated',
        'cancelled'
      ));
  END IF;

  -- Permission actions (include create + submit)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'docutracker_permissions_action_check_prod_v1'
  ) THEN
    ALTER TABLE docutracker_permissions
      DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check_v1;
    ALTER TABLE docutracker_permissions
      ADD CONSTRAINT docutracker_permissions_action_check_prod_v1
      CHECK (action IN (
        'view',
        'create',
        'submit',
        'download',
        'edit',
        'delete',
        'forward',
        'approve',
        'reject',
        'return'
      ));
  END IF;
END $$;

-- Routing config JSON must be an array (if you keep JSONB workflow configs)
ALTER TABLE docutracker_routing_configs
  DROP CONSTRAINT IF EXISTS docutracker_routing_configs_steps_is_array_check_prod_v1;
ALTER TABLE docutracker_routing_configs
  ADD CONSTRAINT docutracker_routing_configs_steps_is_array_check_prod_v1
  CHECK (jsonb_typeof(steps) = 'array');

-- Numeric guards
ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_current_step_check_prod_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_current_step_check_prod_v1
  CHECK (current_step IS NULL OR current_step >= 1);

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_escalation_level_check_prod_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_escalation_level_check_prod_v1
  CHECK (escalation_level >= 0);

ALTER TABLE docutracker_routing_records
  DROP CONSTRAINT IF EXISTS docutracker_routing_records_step_order_check_prod_v1;
ALTER TABLE docutracker_routing_records
  ADD CONSTRAINT docutracker_routing_records_step_order_check_prod_v1
  CHECK (step_order >= 1);

ALTER TABLE docutracker_routing_configs
  DROP CONSTRAINT IF EXISTS docutracker_routing_configs_review_deadline_hours_check_prod_v1;
ALTER TABLE docutracker_routing_configs
  ADD CONSTRAINT docutracker_routing_configs_review_deadline_hours_check_prod_v1
  CHECK (review_deadline_hours > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_escalation_delay_minutes_check_prod_v1;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_escalation_delay_minutes_check_prod_v1
  CHECK (escalation_delay_minutes > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_max_escalation_level_check_prod_v1;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_max_escalation_level_check_prod_v1
  CHECK (max_escalation_level >= 1);

-- ============================================================
-- SECTION 3) PERMISSIONS: HYGIENE + UNIQUENESS + XOR SCOPE
-- ============================================================
-- Remove meaningless rows (no scope).
DELETE FROM docutracker_permissions
WHERE user_id IS NULL AND role_id IS NULL;

-- De-duplicate rows deterministically (keep newest).
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
WHERE p.id = r.id AND r.rn > 1;

ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_scope_check_prod_v2;
ALTER TABLE docutracker_permissions
  ADD CONSTRAINT docutracker_permissions_scope_check_prod_v2
  CHECK ((user_id IS NOT NULL) <> (role_id IS NOT NULL));

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_user_unique
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_role_unique
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;

-- ============================================================
-- SECTION 3A) ROLES: CANONICAL ROLES + LEGACY ALIASES (DB-level normalization)
-- ============================================================
-- This does NOT change your HRMS "users.role" storage. It only standardizes
-- DocuTracker's understanding of role ids.
CREATE TABLE IF NOT EXISTS docutracker_roles (
  role_id TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO docutracker_roles(role_id)
VALUES ('admin'), ('hr'), ('supervisor'), ('employee')
ON CONFLICT (role_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS docutracker_role_aliases (
  alias TEXT PRIMARY KEY,
  role_id TEXT NOT NULL REFERENCES docutracker_roles(role_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO docutracker_role_aliases(alias, role_id)
VALUES ('hr_staff', 'hr'), ('dept_head', 'supervisor')
ON CONFLICT (alias) DO NOTHING;

-- Enforce that role-based permission rows use canonical roles (prevents drift).
-- If you still need to insert legacy values, insert them into docutracker_role_aliases instead.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'docutracker_permissions_role_fk_prod_v1'
  ) THEN
    ALTER TABLE docutracker_permissions
      ADD CONSTRAINT docutracker_permissions_role_fk_prod_v1
      FOREIGN KEY (role_id) REFERENCES docutracker_roles(role_id)
      DEFERRABLE INITIALLY DEFERRED
      NOT VALID;

    -- Validate after creation. If this fails, you have unexpected legacy/typo
    -- role ids stored in docutracker_permissions.role_id.
    BEGIN
      ALTER TABLE docutracker_permissions
        VALIDATE CONSTRAINT docutracker_permissions_role_fk_prod_v1;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION
        'Cannot validate canonical role FK on docutracker_permissions.role_id. Normalize existing role_id values (or add aliases) then re-run.';
    END;
  END IF;
END $$;

-- ============================================================
-- SECTION 3B) EFFECTIVE PERMISSION FUNCTIONS (single source of truth)
-- ============================================================
-- Normalize role ids inside the database (legacy aliases -> canonical).
CREATE OR REPLACE FUNCTION docutracker_normalize_role(p_role_id TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(btrim(coalesce(p_role_id, '')))
    WHEN '' THEN ''
    WHEN 'hr_staff' THEN 'hr'
    WHEN 'dept_head' THEN 'supervisor'
    ELSE lower(btrim(coalesce(p_role_id, '')))
  END
$$;

-- Returns the effective permission according to DocuTracker precedence:
-- 1) user override (document_type)
-- 2) user override (*)
-- 3) role baseline (document_type) [role normalized]
-- 4) role baseline (*)
-- 5) default deny
CREATE OR REPLACE FUNCTION docutracker_has_permission(
  p_user_id UUID,
  p_role_id TEXT,
  p_document_type TEXT,
  p_action TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
WITH args AS (
  SELECT
    p_user_id AS user_id,
    docutracker_normalize_role(p_role_id) AS role_id,
    p_document_type AS document_type,
    p_action AS action
),
candidates AS (
  SELECT 1 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 2 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = '*'
    AND p.action = a.action

  UNION ALL
  SELECT 3 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 4 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = '*'
    AND p.action = a.action
)
SELECT COALESCE(
  (SELECT granted FROM candidates ORDER BY prio LIMIT 1),
  false
);
$$;

-- Same check, but returns why (useful for admin UI + debugging).
CREATE OR REPLACE FUNCTION docutracker_permission_explain(
  p_user_id UUID,
  p_role_id TEXT,
  p_document_type TEXT,
  p_action TEXT
)
RETURNS TABLE (
  granted BOOLEAN,
  source TEXT,
  matched_document_type TEXT
)
LANGUAGE sql
STABLE
AS $$
WITH args AS (
  SELECT
    p_user_id AS user_id,
    docutracker_normalize_role(p_role_id) AS role_id,
    p_document_type AS document_type,
    p_action AS action
),
matches AS (
  SELECT 1 AS prio, p.granted, 'user_override'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 2 AS prio, p.granted, 'user_override'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = '*'
    AND p.action = a.action

  UNION ALL
  SELECT 3 AS prio, p.granted, 'role_baseline'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 4 AS prio, p.granted, 'role_baseline'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = '*'
    AND p.action = a.action
)
SELECT
  COALESCE(m.granted, false) AS granted,
  COALESCE(m.source, 'default_deny') AS source,
  m.matched_document_type
FROM (SELECT * FROM matches ORDER BY prio LIMIT 1) m;
$$;

-- Supporting indexes for fast effective-permission lookups.
CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_user_lookup
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_role_lookup
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;

-- ============================================================
-- SECTION 4) ROUTING RECORDS: CONSISTENCY + "ONE ACTIVE STEP" ENFORCEMENT
-- ============================================================
-- Ensure there is at most one row per (document_id, step_order). This matches
-- the common design where each step is assigned to a single holder at a time.
CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_routing_records_unique_step
  ON docutracker_routing_records(document_id, step_order);

-- Enforce at most one active routing record per document.
-- IMPORTANT: This can fail if your data already has multiple active rows.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
      AND c.relname = 'idx_docutracker_routing_records_one_active_per_doc'
  ) THEN
    BEGIN
      CREATE UNIQUE INDEX idx_docutracker_routing_records_one_active_per_doc
        ON docutracker_routing_records(document_id)
        WHERE status IN ('pending', 'in_review');
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION
        'Cannot enforce one-active-step constraint: existing data has multiple pending/in_review routing_records per document. Fix data then re-run.';
    END;
  END IF;
END $$;

-- ============================================================
-- SECTION 5) NOTIFICATIONS: IDEMPOTENCY + PERFORMANCE
-- ============================================================
ALTER TABLE docutracker_notifications
  ADD COLUMN IF NOT EXISTS event_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_notifications_event_key_unique
  ON docutracker_notifications(document_id, user_id, type, event_key)
  WHERE event_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_read_created
  ON docutracker_notifications(user_id, read, created_at DESC);

-- ============================================================
-- SECTION 6) HISTORY: PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_created_desc
  ON docutracker_document_history(document_id, created_at DESC);

-- ============================================================
-- SECTION 7) DOCUMENT NUMBER GENERATION (DB-side, race-safe)
-- ============================================================
-- 7.1 Sequence table for per-year counters
CREATE TABLE IF NOT EXISTS docutracker_document_number_seq (
  year INT PRIMARY KEY,
  last_value BIGINT NOT NULL DEFAULT 0
);

-- 7.2 Generator function
CREATE OR REPLACE FUNCTION docutracker_next_document_number()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  y INT := EXTRACT(YEAR FROM now())::INT;
  v BIGINT;
BEGIN
  INSERT INTO docutracker_document_number_seq(year, last_value)
  VALUES (y, 0)
  ON CONFLICT (year) DO NOTHING;

  UPDATE docutracker_document_number_seq
  SET last_value = last_value + 1
  WHERE year = y
  RETURNING last_value INTO v;

  RETURN format('DOC-%s-%s', y, lpad(v::TEXT, 6, '0'));
END $$;

-- 7.3 Backfill missing numbers
UPDATE docutracker_documents
SET document_number = docutracker_next_document_number()
WHERE document_number IS NULL OR btrim(document_number) = '';

-- 7.4 Enforce NOT NULL after backfill
ALTER TABLE docutracker_documents
  ALTER COLUMN document_number SET NOT NULL;

-- 7.5 Insert trigger for future rows
CREATE OR REPLACE FUNCTION docutracker_documents_set_doc_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.document_number IS NULL OR btrim(NEW.document_number) = '' THEN
    NEW.document_number := docutracker_next_document_number();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_docutracker_documents_doc_number ON docutracker_documents;
CREATE TRIGGER trg_docutracker_documents_doc_number
BEFORE INSERT ON docutracker_documents
FOR EACH ROW EXECUTE PROCEDURE docutracker_documents_set_doc_number();

-- ============================================================
-- SECTION 8) UPDATED_AT SAFETY (keep timestamps truthful)
-- ============================================================
CREATE OR REPLACE FUNCTION docutracker_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_docutracker_documents_updated_at ON docutracker_documents;
CREATE TRIGGER trg_docutracker_documents_updated_at
BEFORE UPDATE ON docutracker_documents
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_routing_configs_updated_at ON docutracker_routing_configs;
CREATE TRIGGER trg_docutracker_routing_configs_updated_at
BEFORE UPDATE ON docutracker_routing_configs
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_routing_records_updated_at ON docutracker_routing_records;
CREATE TRIGGER trg_docutracker_routing_records_updated_at
BEFORE UPDATE ON docutracker_routing_records
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_permissions_updated_at ON docutracker_permissions;
CREATE TRIGGER trg_docutracker_permissions_updated_at
BEFORE UPDATE ON docutracker_permissions
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_escalation_configs_updated_at ON docutracker_escalation_configs;
CREATE TRIGGER trg_docutracker_escalation_configs_updated_at
BEFORE UPDATE ON docutracker_escalation_configs
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

-- ============================================================
-- SECTION 9) TRANSITION REQUESTS (idempotency + audit of transitions)
-- ============================================================
-- If you already created this table via an earlier migration, this is a no-op.
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

-- ============================================================
-- SECTION 10) QUERY PERFORMANCE INDEXES (inbox, overdue, lists)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_type_status_created
  ON docutracker_documents(document_type, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_holder_status_deadline
  ON docutracker_documents(current_holder_id, status, deadline_time);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_deadline_active
  ON docutracker_documents(deadline_time)
  WHERE status IN ('pending', 'in_review', 'escalated', 'overdue');

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_assignee_status_deadline
  ON docutracker_routing_records(assignee_id, status, deadline_time);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_document_step
  ON docutracker_routing_records(document_id, step_order);

-- End of migration

