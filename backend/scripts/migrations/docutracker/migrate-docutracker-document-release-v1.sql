-- DocuTracker: release / distribution of approved native documents.
--
-- Approval and release are separate stages. A document type can require a
-- release after final approval (docutracker_document_types.requires_release).
-- Such documents stay `approved` and gain a separate release state; the
-- receiving department sees the document only after an authorized user
-- releases it. Release authority is the System Access permission `release`
-- (role or user rows, per document type). Source-module records (DTR, RSP,
-- L&D) never use release.
--
-- Existing documents are not backfilled: release_required defaults to false,
-- so already-approved documents do not become "awaiting release". Documents
-- still in review when this runs follow the type policy at final approval.
--
-- Idempotent. Re-running does not override an admin's release policy.

BEGIN;

-- 1) Per-type release policy. Memo requires release on first application.
INSERT INTO docutracker_document_types (document_type, display_name, description, number_prefix)
VALUES ('memo', 'Memo', 'Internal memorandum document', 'MEMO')
ON CONFLICT (document_type) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'docutracker_document_types'
      AND column_name = 'requires_release'
  ) THEN
    ALTER TABLE docutracker_document_types
      ADD COLUMN requires_release BOOLEAN NOT NULL DEFAULT false;
    UPDATE docutracker_document_types
       SET requires_release = true,
           updated_at = now()
     WHERE document_type = 'memo';
  END IF;
END $$;

-- 2) Release state on documents. Names are snapshotted for the audit record.
ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS release_required BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS released_to_department_id UUID
    REFERENCES departments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS released_to_department_name TEXT,
  ADD COLUMN IF NOT EXISTS released_by UUID
    REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS released_by_name TEXT,
  ADD COLUMN IF NOT EXISTS released_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS release_remarks TEXT;

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_release_native_check_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_release_native_check_v1
  CHECK (NOT release_required OR source_module IS NULL) NOT VALID;
ALTER TABLE docutracker_documents
  VALIDATE CONSTRAINT docutracker_documents_release_native_check_v1;

ALTER TABLE docutracker_documents
  DROP CONSTRAINT IF EXISTS docutracker_documents_release_state_check_v1;
ALTER TABLE docutracker_documents
  ADD CONSTRAINT docutracker_documents_release_state_check_v1
  CHECK (
    released_at IS NULL
    OR (
      release_required
      AND btrim(COALESCE(released_to_department_name, '')) <> ''
    )
  ) NOT VALID;
ALTER TABLE docutracker_documents
  VALIDATE CONSTRAINT docutracker_documents_release_state_check_v1;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_released_to_department
  ON docutracker_documents(released_to_department_id, released_at DESC)
  WHERE released_at IS NOT NULL;

-- 3) History: the `released` event with structured department details.
ALTER TABLE docutracker_document_history
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE docutracker_document_history
  DROP CONSTRAINT IF EXISTS chk_docutracker_history_action;
ALTER TABLE docutracker_document_history
  ADD CONSTRAINT chk_docutracker_history_action
  CHECK (action IS NULL OR action IN (
    'created',
    'submitted',
    'forwarded',
    'approved',
    'rejected',
    'returned',
    'metadata_updated',
    'remark',
    'escalated',
    'overdue',
    'assigned',
    'signed',
    'released'
  )) NOT VALID;
ALTER TABLE docutracker_document_history
  VALIDATE CONSTRAINT chk_docutracker_history_action;

-- 4) Notifications: receiving-department members are told about a release.
ALTER TABLE docutracker_notifications
  DROP CONSTRAINT IF EXISTS docutracker_notifications_type_check;
ALTER TABLE docutracker_notifications
  ADD CONSTRAINT docutracker_notifications_type_check
  CHECK (type IN (
    'assigned', 'deadline_near', 'overdue', 'escalated', 'returned', 'rejected',
    'released'
  )) NOT VALID;
ALTER TABLE docutracker_notifications
  VALIDATE CONSTRAINT docutracker_notifications_type_check;

-- 5) Release authority is a System Access permission.
ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check_prod_v1;
ALTER TABLE docutracker_permissions
  ADD CONSTRAINT docutracker_permissions_action_check_prod_v1
  CHECK (action IN (
    'view', 'create', 'create_draft', 'submit', 'download', 'edit', 'delete',
    'forward', 'approve', 'reject', 'return', 'release'
  )) NOT VALID;
ALTER TABLE docutracker_permissions
  VALIDATE CONSTRAINT docutracker_permissions_action_check_prod_v1;

-- HR releases Memos by default. DO NOTHING keeps an admin's later choice.
INSERT INTO docutracker_permissions (role_id, user_id, document_type, action, granted)
VALUES ('hr', NULL::uuid, 'memo', 'release', true)
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO NOTHING;

COMMIT;
