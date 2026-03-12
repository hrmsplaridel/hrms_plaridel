-- Add department_number to existing departments table
-- Run: psql -U postgres -d hrms_plaridel -f scripts/migrate-add-department-number.sql

CREATE SEQUENCE IF NOT EXISTS departments_department_number_seq;

ALTER TABLE departments
  ADD COLUMN IF NOT EXISTS department_number INT UNIQUE;

-- Backfill: assign 1, 2, 3, ... to rows that have NULL (order by name)
WITH numbered AS (
  SELECT id, row_number() OVER (ORDER BY name, id) AS rn
  FROM departments
  WHERE department_number IS NULL
)
UPDATE departments
SET department_number = numbered.rn
FROM numbered
WHERE departments.id = numbered.id;

SELECT setval(
  'departments_department_number_seq',
  (SELECT COALESCE(MAX(department_number), 1) FROM departments)
);

CREATE INDEX IF NOT EXISTS idx_departments_department_number ON departments(department_number);
