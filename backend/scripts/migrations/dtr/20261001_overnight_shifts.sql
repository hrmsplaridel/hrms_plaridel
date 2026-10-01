BEGIN;
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS break_start TIME;
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS capture_window_minutes INT NOT NULL DEFAULT 120
  CHECK (capture_window_minutes BETWEEN 0 AND 240);
ALTER TABLE dtr_daily_summary ADD COLUMN IF NOT EXISTS shift_snapshot JSONB;
COMMENT ON COLUMN dtr_daily_summary.shift_snapshot IS 'Effective attendance schedule used to process this attendance date.';
COMMIT;
