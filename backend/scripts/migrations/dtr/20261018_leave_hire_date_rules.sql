-- Optional hire-date rules. Existing types keep their full annual allowance.
BEGIN;
ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS minimum_service_months INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS first_year_allowance TEXT NOT NULL DEFAULT 'full';

ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_leave_type_minimum_service_months;
ALTER TABLE leave_types ADD CONSTRAINT chk_leave_type_minimum_service_months
  CHECK (minimum_service_months BETWEEN 0 AND 1200);
ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_leave_type_first_year_allowance;
ALTER TABLE leave_types ADD CONSTRAINT chk_leave_type_first_year_allowance
  CHECK (first_year_allowance IN ('full', 'prorated') AND (
    first_year_allowance = 'full' OR (
      entitlement_basis = 'annual' AND max_days IS NOT NULL AND max_days > 0
      AND balance_ledger_type = 'none'
    )
  ));
COMMIT;
