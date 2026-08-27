BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE policy_assignments
  DROP CONSTRAINT IF EXISTS policy_assignments_no_overlapping_employee_ranges;

ALTER TABLE policy_assignments
  ADD CONSTRAINT policy_assignments_no_overlapping_employee_ranges
  EXCLUDE USING gist (
    employee_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
  WHERE (
    is_active = true
    AND employee_id IS NOT NULL
    AND department_id IS NULL
    AND shift_id IS NULL
  );

CREATE INDEX IF NOT EXISTS idx_policy_assignments_employee_effective_range
  ON policy_assignments (employee_id, effective_from, effective_to)
  WHERE (
    is_active = true
    AND employee_id IS NOT NULL
    AND department_id IS NULL
    AND shift_id IS NULL
  );

COMMENT ON CONSTRAINT policy_assignments_no_overlapping_employee_ranges
  ON policy_assignments IS
  'An employee can have only one enabled employee-level attendance policy on a date.';

COMMIT;
