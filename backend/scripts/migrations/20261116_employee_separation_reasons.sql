-- Run after 20261116_employee_return_to_service.sql.
-- Add explicit deceased and contract-expired separation reasons.
BEGIN;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_employment_status_check;
ALTER TABLE users ADD CONSTRAINT users_employment_status_check
  CHECK (employment_status IN (
    'active', 'inactive', 'resigned', 'retired', 'terminated',
    'deceased', 'contract_expired'
  ));

-- Deceased employees cannot return; an expired contract can start a new period.
ALTER TABLE employee_service_returns
  DROP CONSTRAINT IF EXISTS employee_service_returns_prior_employment_status_check;
ALTER TABLE employee_service_returns
  ADD CONSTRAINT employee_service_returns_prior_employment_status_check
  CHECK (prior_employment_status IN ('resigned', 'retired', 'terminated', 'contract_expired'));

COMMIT;
