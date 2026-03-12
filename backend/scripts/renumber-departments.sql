-- One-time: renumber all departments to 1, 2, 3, ... (no gaps)
-- Run: psql -U postgres -d hrms_plaridel -f scripts/renumber-departments.sql

WITH numbered AS (
  SELECT id, row_number() OVER (ORDER BY name, id) AS rn
  FROM departments
)
UPDATE departments
SET department_number = numbered.rn
FROM numbered
WHERE departments.id = numbered.id;

-- Keep sequence in sync for any code that still uses it
SELECT setval(
  'departments_department_number_seq',
  (SELECT COALESCE(MAX(department_number), 1) FROM departments)
);
