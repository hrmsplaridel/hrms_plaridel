-- Allow the server-audited e-signature event in DocuTracker history.
-- Safe to re-run after the document builder/e-signature migration.

BEGIN;

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
    'signed'
  )) NOT VALID;

ALTER TABLE docutracker_document_history
  VALIDATE CONSTRAINT chk_docutracker_history_action;

COMMIT;
