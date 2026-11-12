-- Custom credit wallets and opt-in monthly accrual. Run before deploying backend.
BEGIN;
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS accrual_start_date DATE;
ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_custom_leave_accrual;
ALTER TABLE leave_types ADD CONSTRAINT chk_custom_leave_accrual CHECK (
  is_system OR name IN ('vacationLeave','sickLeave') OR (
    (NOT accrues_monthly AND accrual_monthly_rate IS NULL
      AND accrual_start_date IS NULL AND accrual_annual_cap IS NULL)
    OR (accrues_monthly AND balance_ledger_type = 'ownBalance'
      AND entitlement_basis = 'accrual' AND accrual_monthly_rate > 0
      AND accrual_monthly_rate IS NOT NULL AND accrual_start_date IS NOT NULL
      AND EXTRACT(DAY FROM accrual_start_date) = 1
      AND (accrual_annual_cap IS NULL OR accrual_annual_cap > 0))
  )
);
-- The FK still permits only names registered in leave_types.
ALTER TABLE leave_balances DROP CONSTRAINT IF EXISTS chk_leave_balances_leave_type;
COMMIT;
