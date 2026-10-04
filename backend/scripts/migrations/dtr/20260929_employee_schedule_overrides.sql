BEGIN;

CREATE TABLE IF NOT EXISTS employee_schedule_overrides (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  schedule_date DATE NOT NULL,
  is_working_day BOOLEAN NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_schedule_overrides_employee_date_key
    UNIQUE (employee_id, schedule_date)
);

CREATE INDEX IF NOT EXISTS idx_employee_schedule_overrides_date_employee
  ON employee_schedule_overrides (schedule_date, employee_id);

DROP TRIGGER IF EXISTS trg_employee_schedule_overrides_updated_at
  ON employee_schedule_overrides;
CREATE TRIGGER trg_employee_schedule_overrides_updated_at
BEFORE UPDATE ON employee_schedule_overrides
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

COMMIT;
