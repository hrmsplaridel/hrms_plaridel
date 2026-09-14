-- Allow genuinely incomplete leave drafts while submission remains strict in the API.
BEGIN;

ALTER TABLE leave_requests
  ALTER COLUMN start_date DROP NOT NULL,
  ALTER COLUMN end_date DROP NOT NULL;

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_submission_dates;
ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_submission_dates CHECK (
    status = 'draft' OR (start_date IS NOT NULL AND end_date IS NOT NULL)
  );

COMMIT;
