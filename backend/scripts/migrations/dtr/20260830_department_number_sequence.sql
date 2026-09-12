-- Migration: Preserve monotonically increasing department numbers
-- Purpose: Move the sequence above every number already issued before inserts
--          begin relying on the departments table default.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260830_department_number_sequence.sql

BEGIN;

LOCK TABLE departments IN SHARE ROW EXCLUSIVE MODE;

SELECT setval(
  'departments_department_number_seq',
  GREATEST(
    (SELECT COALESCE(MAX(department_number), 0) FROM departments),
    (SELECT last_value FROM departments_department_number_seq),
    1
  ),
  true
);

COMMIT;
