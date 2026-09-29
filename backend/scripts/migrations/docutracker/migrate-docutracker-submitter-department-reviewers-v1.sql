-- DocuTracker: submitter department reviewers + originating department snapshot
--
-- 1) Allows workflow steps to resolve assignees from the document creator's
--    department head (+ backups) at routing time.
-- 2) Snapshots originating_department_id on documents for queues/audit.

BEGIN;

ALTER TABLE docutracker_workflow_steps
  DROP CONSTRAINT IF EXISTS docutracker_workflow_steps_assignee_source_check;

ALTER TABLE docutracker_workflow_steps
  ADD CONSTRAINT docutracker_workflow_steps_assignee_source_check
  CHECK (
    assignee_source IN (
      'specific_users',
      'department_reviewers',
      'submitter_department_reviewers'
    )
  );

ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS originating_department_id UUID
    REFERENCES departments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_originating_department
  ON docutracker_documents(originating_department_id)
  WHERE originating_department_id IS NOT NULL;

COMMIT;
