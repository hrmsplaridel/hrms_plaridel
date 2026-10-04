-- Reject leave-type rules that would silently disable filing or behave ambiguously.
-- Run: psql -v ON_ERROR_STOP=1 -d hrms_plaridel -f backend/scripts/migrations/dtr/20260926_leave_type_numeric_constraints.sql

BEGIN;

UPDATE leave_types
SET max_days = NULL,
    updated_at = now()
WHERE max_days IS NOT NULL
  AND max_days <= 0;

UPDATE leave_types
SET requires_attachment_when_over_days = NULL,
    updated_at = now()
WHERE requires_attachment_when_over_days IS NOT NULL
  AND requires_attachment_when_over_days <= 0;

UPDATE leave_types
SET minimum_advance_days = NULL,
    updated_at = now()
WHERE minimum_advance_days IS NOT NULL
  AND minimum_advance_days < 0;

ALTER TABLE leave_types
  DROP CONSTRAINT IF EXISTS chk_leave_type_max_days_positive,
  DROP CONSTRAINT IF EXISTS chk_leave_type_attachment_threshold_positive,
  DROP CONSTRAINT IF EXISTS chk_leave_type_minimum_advance_days_nonnegative;

ALTER TABLE leave_types
  ADD CONSTRAINT chk_leave_type_max_days_positive
    CHECK (max_days IS NULL OR max_days > 0),
  ADD CONSTRAINT chk_leave_type_attachment_threshold_positive
    CHECK (
      requires_attachment_when_over_days IS NULL
      OR requires_attachment_when_over_days > 0
    ),
  ADD CONSTRAINT chk_leave_type_minimum_advance_days_nonnegative
    CHECK (minimum_advance_days IS NULL OR minimum_advance_days >= 0);

COMMIT;
