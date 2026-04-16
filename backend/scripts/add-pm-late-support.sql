-- Add PM late detection support.
-- Run: psql -U postgres -d hrms_plaridel -f backend/scripts/add-pm-late-support.sql
--
-- break_end: when PM shift starts (e.g. 13:00 for 8-5 shift with 1hr lunch).
-- pm_status: 'present' | 'late' | null (null = absent or no break_in).

-- 1. Add break_end to shifts (PM resume time)
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS break_end TIME;

COMMENT ON COLUMN shifts.break_end IS 'PM shift start time (e.g. 13:00 for 1PM resume after lunch)';

-- 2. Add override_break_end to assignments (per-employee override)
ALTER TABLE assignments ADD COLUMN IF NOT EXISTS override_break_end TIME;

-- 3. Add pm_status to dtr_daily_summary
ALTER TABLE dtr_daily_summary ADD COLUMN IF NOT EXISTS pm_status TEXT
  CHECK (pm_status IS NULL OR pm_status IN ('present', 'late'));
