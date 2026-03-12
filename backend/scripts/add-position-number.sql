-- Add position_number to positions (like department_number).
-- Run in pgAdmin against database: hrms_plaridel

-- 1. Create sequence for new position numbers
CREATE SEQUENCE IF NOT EXISTS positions_position_number_seq;

-- 2. Add column (nullable first so we can backfill)
ALTER TABLE positions ADD COLUMN IF NOT EXISTS position_number INT;

-- 3. Backfill existing rows with 1, 2, 3, ...
WITH numbered AS (
  SELECT id, row_number() OVER (ORDER BY created_at, id) AS r
  FROM positions
  WHERE position_number IS NULL
)
UPDATE positions
SET position_number = numbered.r
FROM numbered
WHERE positions.id = numbered.id;

-- 4. Set default for new rows
ALTER TABLE positions
  ALTER COLUMN position_number SET DEFAULT nextval('positions_position_number_seq');

-- 5. Move sequence to after max existing number
SELECT setval(
  'positions_position_number_seq',
  (SELECT COALESCE(MAX(position_number), 1) FROM positions)
);

-- 6. Enforce unique (skip if already added)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_positions_position_number'
  ) THEN
    ALTER TABLE positions ADD CONSTRAINT uq_positions_position_number UNIQUE (position_number);
  END IF;
END $$;

-- 7. Optional: make NOT NULL after backfill (uncomment if you want)
-- ALTER TABLE positions ALTER COLUMN position_number SET NOT NULL;
