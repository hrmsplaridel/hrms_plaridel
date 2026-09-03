BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS leave_credit_eligible_until DATE;

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS chk_users_separation_after_hire;

ALTER TABLE users
  ADD CONSTRAINT chk_users_separation_after_hire
  CHECK (
    separation_date IS NULL
    OR date_hired IS NULL
    OR separation_date >= date_hired
  ) NOT VALID;

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS chk_users_credit_eligibility_end;

ALTER TABLE users
  ADD CONSTRAINT chk_users_credit_eligibility_end
  CHECK (
    leave_credit_eligible_until IS NULL
    OR (
      separation_date IS NOT NULL
      AND leave_credit_eligible_until = separation_date
    )
  ) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_users_leave_credit_eligible_until
  ON users (leave_credit_eligible_until)
  WHERE leave_credit_eligible_until IS NOT NULL;

COMMENT ON COLUMN users.leave_credit_eligible_until IS
  'Final service date through which a separated employee remains eligible for VL/SL accrual processing.';

COMMIT;
