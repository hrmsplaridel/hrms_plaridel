-- Simplify shifts: add working_days, remove code, break, crosses_midnight
-- Run on existing DBs: psql -U postgres -d hrms_plaridel -f backend/scripts/migrate-shifts-working-days.sql
--
-- working_days: INTEGER[] with ISO weekday 1=Monday..7=Sunday
-- Default [1,2,3,4,5] = Mon-Fri

-- Drop generated column first (depends on break_start/break_end)
ALTER TABLE shifts DROP COLUMN IF EXISTS break_minutes;

-- Drop constraint that references break columns
ALTER TABLE shifts DROP CONSTRAINT IF EXISTS chk_shift_break_pair;

-- Remove old columns
ALTER TABLE shifts DROP COLUMN IF EXISTS code;
ALTER TABLE shifts DROP COLUMN IF EXISTS break_start;
ALTER TABLE shifts DROP COLUMN IF EXISTS break_end;
ALTER TABLE shifts DROP COLUMN IF EXISTS crosses_midnight;

-- Add working_days (1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun)
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS working_days INT[] NOT NULL DEFAULT ARRAY[1,2,3,4,5];
