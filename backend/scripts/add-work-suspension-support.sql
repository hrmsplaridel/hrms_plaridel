-- Work Suspension support: extend holiday_type and add coverage (whole_day | am_only | pm_only).
-- Run on existing DBs: psql -U youruser -d hrms_plaridel -f scripts/add-work-suspension-support.sql

-- 1. Extend holiday_type to include 'work_suspension'
ALTER TABLE holidays DROP CONSTRAINT IF EXISTS holidays_holiday_type_check;
ALTER TABLE holidays ADD CONSTRAINT holidays_holiday_type_check
  CHECK (holiday_type IN ('regular', 'special', 'local', 'work_suspension'));

-- 2. Add coverage column (whole_day | am_only | pm_only)
ALTER TABLE holidays
  ADD COLUMN IF NOT EXISTS coverage TEXT NOT NULL DEFAULT 'whole_day';
ALTER TABLE holidays DROP CONSTRAINT IF EXISTS holidays_coverage_check;
ALTER TABLE holidays ADD CONSTRAINT holidays_coverage_check
  CHECK (coverage IN ('whole_day', 'am_only', 'pm_only'));

-- Ensure existing rows have whole_day
UPDATE holidays SET coverage = 'whole_day' WHERE coverage IS NULL OR coverage = '';
