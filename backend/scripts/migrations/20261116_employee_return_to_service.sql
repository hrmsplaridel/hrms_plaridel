-- Preserve completed service periods when a separated employee returns.
BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_service_return_date DATE;

CREATE TABLE IF NOT EXISTS employee_service_returns (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_started_on DATE NOT NULL,
  separated_on DATE NOT NULL,
  returned_on DATE NOT NULL,
  prior_employment_status TEXT NOT NULL
    CHECK (prior_employment_status IN ('resigned', 'retired', 'terminated')),
  leave_credit_eligible BOOLEAN NOT NULL,
  reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 5 AND 2000),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_service_returns_dates_check
    CHECK (service_started_on <= separated_on AND separated_on < returned_on),
  CONSTRAINT employee_service_returns_employee_date_key UNIQUE (employee_id, returned_on)
);

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_service_return_dates_check;
ALTER TABLE users ADD CONSTRAINT users_service_return_dates_check CHECK (
  last_service_return_date IS NULL OR (
    (date_hired IS NULL OR last_service_return_date >= date_hired)
    AND (separation_date IS NULL OR separation_date >= last_service_return_date)
  )
);

COMMIT;
