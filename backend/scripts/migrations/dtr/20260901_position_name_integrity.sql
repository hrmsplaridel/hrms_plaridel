-- Migration: Position name integrity
-- Purpose: Reject blank names and enforce normalized uniqueness per department.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260901_position_name_integrity.sql

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM positions
     WHERE BTRIM(name) = ''
  ) THEN
    RAISE EXCEPTION 'Blank position names must be corrected before applying this migration';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM positions
     GROUP BY LOWER(BTRIM(name)), department_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Normalized duplicate position names within a department must be corrected before applying this migration';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'chk_positions_name_not_blank'
       AND conrelid = 'positions'::regclass
  ) THEN
    ALTER TABLE positions
      ADD CONSTRAINT chk_positions_name_not_blank
      CHECK (BTRIM(name) <> '');
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_positions_name_department_ci
  ON positions (
    LOWER(BTRIM(name)),
    (COALESCE(department_id, '00000000-0000-0000-0000-000000000000'::uuid))
  );

ALTER TABLE positions
  DROP CONSTRAINT IF EXISTS uq_positions_name_department;

COMMIT;
