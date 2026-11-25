-- Duty roster: optional shift per employee per date (rotating morning/afternoon/night duty).
-- NULL keeps the assignment's regular shift. Idempotent.
-- Run: psql -v ON_ERROR_STOP=1 -d <db> -f backend/scripts/migrations/dtr/20261125_duty_roster_shift.sql

ALTER TABLE employee_schedule_overrides
  ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES shifts(id) ON DELETE RESTRICT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'employee_schedule_overrides_roster_working_day_check'
      AND conrelid = 'employee_schedule_overrides'::regclass
  ) THEN
    ALTER TABLE employee_schedule_overrides
      ADD CONSTRAINT employee_schedule_overrides_roster_working_day_check
      CHECK (shift_id IS NULL OR is_working_day = true);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_employee_schedule_overrides_shift_id
  ON employee_schedule_overrides (shift_id)
  WHERE shift_id IS NOT NULL;

COMMENT ON COLUMN employee_schedule_overrides.shift_id IS
  'Duty roster shift for this date; NULL uses the assignment''s regular shift.';
