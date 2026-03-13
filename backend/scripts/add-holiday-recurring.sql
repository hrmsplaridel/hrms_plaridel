-- Add recurring flag to holidays (apply same month/day every year).
-- Required for "Repeat every year" in Holiday Management. Run on existing DBs:
--   psql -U youruser -d hrms_plaridel -f scripts/add-holiday-recurring.sql

ALTER TABLE holidays
  ADD COLUMN IF NOT EXISTS recurring BOOLEAN NOT NULL DEFAULT false;
