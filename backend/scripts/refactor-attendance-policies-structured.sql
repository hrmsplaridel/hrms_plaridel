-- Migration: Structured Attendance Policies (remove free-text rules)
-- Date: 2026-03-17
--
-- Adds structured computation settings to attendance_policies.
-- Keeps old columns for now (grace_period_minutes, *_rule) for backward compatibility,
-- but the API/UI no longer uses them.

ALTER TABLE attendance_policies
  ADD COLUMN IF NOT EXISTS work_hours_per_day NUMERIC(4,2) NOT NULL DEFAULT 8 CHECK (work_hours_per_day > 0),
  ADD COLUMN IF NOT EXISTS use_equivalent_day_conversion BOOLEAN NOT NULL DEFAULT true,

  ADD COLUMN IF NOT EXISTS deduct_late BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_late_minutes_per_month INT CHECK (max_late_minutes_per_month IS NULL OR max_late_minutes_per_month >= 0),
  ADD COLUMN IF NOT EXISTS convert_late_to_equivalent_day BOOLEAN NOT NULL DEFAULT true,

  ADD COLUMN IF NOT EXISTS deduct_undertime BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS convert_undertime_to_equivalent_day BOOLEAN NOT NULL DEFAULT true,

  ADD COLUMN IF NOT EXISTS absent_equals_full_day_deduction BOOLEAN NOT NULL DEFAULT true,

  ADD COLUMN IF NOT EXISTS combine_late_and_undertime BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deduction_multiplier NUMERIC(6,3) NOT NULL DEFAULT 1.0 CHECK (deduction_multiplier > 0);

-- Optional (later): drop deprecated columns when safe
  -- ALTER TABLE attendance_policies
  --   DROP COLUMN IF EXISTS grace_period_minutes,
  --   DROP COLUMN IF EXISTS late_deduction_rule,
  --   DROP COLUMN IF EXISTS absent_deduction_rule,
  --   DROP COLUMN IF EXISTS undertime_rule,
  --   DROP COLUMN IF EXISTS max_late_per_month_minutes;

