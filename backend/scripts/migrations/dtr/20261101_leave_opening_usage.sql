-- Existing openings remain unverified until HR supplies the cutoff-year usage.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE leave_opening_balance_setups
  ADD COLUMN IF NOT EXISTS qualifying_leave_days NUMERIC(10,3),
  ADD COLUMN IF NOT EXISTS usage_reference TEXT,
  ADD COLUMN IF NOT EXISTS usage_verified_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS usage_verified_at TIMESTAMPTZ;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='leave_opening_balance_setups'::regclass AND conname='leave_opening_usage_check') THEN
    ALTER TABLE leave_opening_balance_setups ADD CONSTRAINT leave_opening_usage_check CHECK (
      (qualifying_leave_days IS NULL AND usage_reference IS NULL AND usage_verified_at IS NULL)
      OR (qualifying_leave_days IS NOT NULL AND qualifying_leave_days BETWEEN 0 AND 366
        AND usage_reference IS NOT NULL AND btrim(usage_reference) <> '' AND usage_verified_at IS NOT NULL)
    );
  END IF;
END $$;
COMMIT;
