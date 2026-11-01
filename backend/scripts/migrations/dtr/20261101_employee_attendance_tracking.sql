-- Employee-level tracking boundary, configured from Assignments. Existing data keeps legacy behavior.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE users ADD COLUMN IF NOT EXISTS attendance_tracking_start_date DATE;
COMMIT;
