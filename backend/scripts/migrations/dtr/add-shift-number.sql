-- Add shift_number to shifts (like department_number / position_number).
-- Run in pgAdmin against database: hrms_plaridel

CREATE SEQUENCE IF NOT EXISTS shifts_shift_number_seq;

ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_number INT;

WITH numbered AS (
  SELECT id, row_number() OVER (ORDER BY created_at, id) AS r
  FROM shifts
  WHERE shift_number IS NULL
)
UPDATE shifts
SET shift_number = numbered.r
FROM numbered
WHERE shifts.id = numbered.id;

ALTER TABLE shifts
  ALTER COLUMN shift_number SET DEFAULT nextval('shifts_shift_number_seq');

SELECT setval(
  'shifts_shift_number_seq',
  (SELECT COALESCE(MAX(shift_number), 1) FROM shifts)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_shifts_shift_number'
  ) THEN
    ALTER TABLE shifts ADD CONSTRAINT uq_shifts_shift_number UNIQUE (shift_number);
  END IF;
END $$;
