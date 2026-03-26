-- Leave Module Schema Alignment (Flutter LeaveRequest ↔ PostgreSQL)
-- Run on existing DBs:
--   psql -U postgres -d hrms_plaridel -f backend/scripts/migrate-leave-schema-alignment.sql
--
-- Goals:
-- - Expand leave_requests to support draft/returned workflow + reviewer fields + details payload.
-- - Add user_id column while keeping employee_id for backward compatibility (DTR queries currently use employee_id).
-- - Add number_of_days (alias to total_days) and details JSONB for richer Flutter fields.
-- - Do NOT add any Supabase-specific schema.

BEGIN;

-- 1) leave_requests: add missing columns (non-destructive)
ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS number_of_days NUMERIC(5,2);

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS details JSONB;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS reviewer_remarks TEXT;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- 2) Backfill user_id and number_of_days where possible
UPDATE leave_requests
SET user_id = employee_id
WHERE user_id IS NULL AND employee_id IS NOT NULL;

UPDATE leave_requests
SET number_of_days = total_days
WHERE number_of_days IS NULL AND total_days IS NOT NULL;

-- 3) Keep existing approved_by/approved_at but backfill reviewer fields for already-approved records
UPDATE leave_requests
SET reviewer_id = COALESCE(reviewer_id, approved_by),
    reviewed_at = COALESCE(reviewed_at, approved_at)
WHERE (approved_by IS NOT NULL OR approved_at IS NOT NULL);

-- 4) Update status constraint to include draft/returned and align naming
-- Drop existing CHECK constraint if present (name can differ across DBs; attempt common patterns).
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_status_check;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS chk_leave_requests_status;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_requests_status
  CHECK (status IN ('draft','pending','returned','approved','rejected','cancelled'));

-- 5) Ensure date integrity constraints exist (keep originals if present)
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS chk_leave_dates;
ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_dates CHECK (end_date >= start_date);

ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS chk_leave_total_days;
ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_total_days CHECK (
    (total_days IS NULL OR total_days >= 0)
    AND (number_of_days IS NULL OR number_of_days >= 0)
  );

-- 6) Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_leave_requests_user_id ON leave_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_reviewer_id ON leave_requests(reviewer_id);

COMMIT;

