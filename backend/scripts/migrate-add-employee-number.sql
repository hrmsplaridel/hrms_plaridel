-- Add employee_number to existing users table
-- Run on existing DBs: psql -U postgres -d hrms_plaridel -f scripts/migrate-add-employee-number.sql
-- (Use your DB user; set PGPASSWORD if you want to avoid password prompt.)

CREATE SEQUENCE IF NOT EXISTS users_employee_number_seq;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS employee_number INT UNIQUE;

-- Backfill: assign 1, 2, 3, ... to rows that have NULL (order by created_at)
WITH numbered AS (
  SELECT id, row_number() OVER (ORDER BY created_at NULLS LAST, id) AS rn
  FROM users
  WHERE employee_number IS NULL
)
UPDATE users
SET employee_number = numbered.rn
FROM numbered
WHERE users.id = numbered.id;

-- Set sequence so next new user gets max(employee_number) + 1
SELECT setval(
  'users_employee_number_seq',
  (SELECT COALESCE(MAX(employee_number), 1) FROM users)
);

CREATE INDEX IF NOT EXISTS idx_users_employee_number ON users(employee_number);
