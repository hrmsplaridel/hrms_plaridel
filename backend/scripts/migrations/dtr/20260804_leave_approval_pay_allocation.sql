-- Store the final HR-approved paid/unpaid split as authoritative request data.
-- Existing approved requests remain NULL and use legacy full-request reversal.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260804_leave_approval_pay_allocation.sql

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS approved_days_with_pay NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS approved_days_without_pay NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS approved_other_details TEXT;

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_approved_days_nonnegative;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_approved_days_nonnegative CHECK (
    (approved_days_with_pay IS NULL OR approved_days_with_pay >= 0)
    AND (approved_days_without_pay IS NULL OR approved_days_without_pay >= 0)
  );
