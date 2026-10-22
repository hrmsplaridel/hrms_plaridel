-- Versioned print-only rule. Existing workflows retain Mayor replacement;
-- filed request snapshots, decisions, permissions and routing are untouched.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE approval_workflow_versions
  ADD COLUMN IF NOT EXISTS self_filing_signatory_policy TEXT NOT NULL DEFAULT 'mayor';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid = 'approval_workflow_versions'::regclass
      AND conname = 'approval_workflow_versions_print_policy_check') THEN
    ALTER TABLE approval_workflow_versions
      ADD CONSTRAINT approval_workflow_versions_print_policy_check
      CHECK (self_filing_signatory_policy IN ('mayor', 'blank', 'actual_reviewer'));
  END IF;
END $$;
COMMIT;
