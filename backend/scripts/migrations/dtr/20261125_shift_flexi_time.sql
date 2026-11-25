-- Flexi-time shifts: start_time is the earliest arrival, flexi_latest_start the latest.
-- NULL keeps the shift fixed. Idempotent.
-- Run: psql -v ON_ERROR_STOP=1 -d <db> -f backend/scripts/migrations/dtr/20261125_shift_flexi_time.sql

ALTER TABLE shifts ADD COLUMN IF NOT EXISTS flexi_latest_start TIME;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'shifts_flexi_latest_start_check'
      AND conrelid = 'shifts'::regclass
  ) THEN
    ALTER TABLE shifts
      ADD CONSTRAINT shifts_flexi_latest_start_check
      CHECK (flexi_latest_start IS NULL OR flexi_latest_start > start_time);
  END IF;
END $$;

COMMENT ON COLUMN shifts.flexi_latest_start IS
  'Flexi-time: latest allowed arrival. NULL = fixed shift. Expected time-out moves with arrival.';
