-- New filings keep the configured primary's printed identity by default.
-- Existing filed request snapshots keep their previous printing behavior.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE approval_workflow_versions
  ADD COLUMN IF NOT EXISTS backup_signatory_policy TEXT NOT NULL DEFAULT 'keep_primary';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid = 'approval_workflow_versions'::regclass
      AND conname = 'approval_workflow_versions_backup_print_policy_check') THEN
    ALTER TABLE approval_workflow_versions
      ADD CONSTRAINT approval_workflow_versions_backup_print_policy_check
      CHECK (backup_signatory_policy IN ('keep_primary', 'actual_reviewer'));
  END IF;
END $$;
COMMIT;
