-- Migrate holidays from single holiday_date to date_from / date_to (inclusive range).
-- Run once on databases created before date-range support. Fresh installs use init-schema only.

ALTER TABLE holidays ADD COLUMN IF NOT EXISTS date_from DATE;
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS date_to DATE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'holidays' AND column_name = 'holiday_date'
  ) THEN
    UPDATE holidays SET date_from = holiday_date, date_to = holiday_date WHERE date_from IS NULL;
  END IF;
END $$;

ALTER TABLE holidays ALTER COLUMN date_from SET NOT NULL;
ALTER TABLE holidays ALTER COLUMN date_to SET NOT NULL;

ALTER TABLE holidays DROP CONSTRAINT IF EXISTS uq_holiday_date_name;
ALTER TABLE holidays DROP CONSTRAINT IF EXISTS chk_holidays_date_range;
ALTER TABLE holidays ADD CONSTRAINT chk_holidays_date_range CHECK (date_to >= date_from);

DROP INDEX IF EXISTS idx_holidays_holiday_date;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'holidays' AND column_name = 'holiday_date'
  ) THEN
    ALTER TABLE holidays DROP COLUMN holiday_date;
  END IF;
END $$;

ALTER TABLE holidays DROP CONSTRAINT IF EXISTS uq_holidays_name_range;
ALTER TABLE holidays ADD CONSTRAINT uq_holidays_name_range UNIQUE (name, date_from, date_to);

CREATE INDEX IF NOT EXISTS idx_holidays_date_range ON holidays(date_from, date_to);
