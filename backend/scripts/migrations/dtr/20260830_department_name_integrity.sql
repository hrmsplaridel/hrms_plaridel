-- Migration: Department name integrity
-- Purpose: Reject blank names and enforce case-insensitive uniqueness.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260830_department_name_integrity.sql

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM departments
     WHERE BTRIM(name) = ''
  ) THEN
    RAISE EXCEPTION 'Blank department names must be corrected before applying this migration';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM departments
     GROUP BY LOWER(BTRIM(name))
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Case-insensitive duplicate department names must be corrected before applying this migration';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'chk_departments_name_not_blank'
       AND conrelid = 'departments'::regclass
  ) THEN
    ALTER TABLE departments
      ADD CONSTRAINT chk_departments_name_not_blank
      CHECK (BTRIM(name) <> '');
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_departments_name_ci
  ON departments (LOWER(BTRIM(name)));

COMMIT;
