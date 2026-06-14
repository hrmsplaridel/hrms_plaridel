-- Migration: Two-stage leave approval workflow
-- Employee → Department Head → HR/Admin
--
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/migrate-leave-approval-workflow.sql
--
-- Safe to re-run (idempotent via IF EXISTS guards).

-- 1. Expand the status CHECK constraint to include new workflow statuses.
--    Old statuses are preserved for backward compatibility.
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_status_check;
ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_status_check
  CHECK (status IN (
    'draft',
    'pending',                       -- legacy: treated as alias for pending_hr
    'pending_department_head',       -- awaiting department head approval
    'pending_hr',                    -- awaiting HR/admin final approval
    'rejected_by_department_head',   -- department head rejected
    'rejected_by_hr',                -- HR/admin rejected
    'returned',                      -- sent back to employee for correction
    'approved',                      -- final approval by HR/admin
    'rejected',                      -- legacy: old single-stage rejection
    'cancelled'                      -- employee cancelled
  ));

-- 2. Rebuild the overlap-prevention unique index to cover new pending statuses.
DROP INDEX IF EXISTS uq_leave_requests_no_overlap;
CREATE UNIQUE INDEX uq_leave_requests_no_overlap
  ON leave_requests (user_id, start_date, end_date)
  WHERE status IN ('pending', 'pending_department_head', 'pending_hr', 'approved');
