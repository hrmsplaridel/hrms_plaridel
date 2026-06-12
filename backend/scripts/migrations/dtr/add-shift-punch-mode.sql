-- Add explicit attendance punch interpretation for shifts.
-- Existing rows default to "auto", preserving the legacy start/end/break-based behavior.

ALTER TABLE shifts
  ADD COLUMN IF NOT EXISTS punch_mode TEXT NOT NULL DEFAULT 'auto';

ALTER TABLE shifts DROP CONSTRAINT IF EXISTS shifts_punch_mode_check;
ALTER TABLE shifts
  ADD CONSTRAINT shifts_punch_mode_check
  CHECK (punch_mode IN ('auto', 'full_day', 'am_only', 'pm_only', 'single_session'));

COMMENT ON COLUMN shifts.punch_mode IS
  'Attendance punch interpretation: auto, full_day, am_only, pm_only, or single_session.';
