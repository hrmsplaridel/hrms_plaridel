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
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'docutracker_permissions_action_check_v1'
  ) THEN
    ALTER TABLE docutracker_permissions
      ADD CONSTRAINT docutracker_permissions_action_check_v1
      CHECK (action IN ('view', 'create', 'edit', 'download', 'delete', 'return', 'forward', 'approve', 'reject', 'submit'));
  END IF;
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
