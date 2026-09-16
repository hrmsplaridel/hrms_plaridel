-- Allow credit-backed leave requests to proceed when some or all days may be unpaid.
-- The exact paid-credit reservation is stored per request for reliable release.

BEGIN;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS reserved_credit_days NUMERIC(10,3);

UPDATE leave_requests lr
SET reserved_credit_days = CASE
  WHEN lr.status IN ('pending', 'pending_department_head', 'pending_hr')
    THEN GREATEST(0, COALESCE(lr.number_of_days, lr.total_days, 0))
  ELSE 0
END
FROM leave_types lt
WHERE lt.id = lr.leave_type_id
  AND COALESCE(NULLIF(lt.balance_ledger_type, ''), 'none') <> 'none'
  AND lr.reserved_credit_days IS NULL;

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_reserved_credit_days_nonnegative;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_reserved_credit_days_nonnegative
  CHECK (reserved_credit_days IS NULL OR reserved_credit_days >= 0);

COMMIT;
