BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- A current assignment and a scheduled future assignment are both valid
-- records. Effective dates, rather than a single active-row flag, determine
-- which one applies on a particular day.
DROP INDEX IF EXISTS uq_assignments_one_active_per_employee;

-- Repair future transfers created by the previous route. That route marked
-- the predecessor inactive immediately and ended it on (rather than before)
-- the future assignment's start date.
WITH future_assignment AS (
  SELECT DISTINCT ON (employee_id)
         employee_id,
         effective_from
  FROM assignments
  WHERE is_active = true
    AND effective_from > CURRENT_DATE
  ORDER BY employee_id, effective_from
), predecessor AS (
  SELECT DISTINCT ON (a.employee_id)
         a.id,
         f.effective_from AS next_effective_from
  FROM assignments a
  JOIN future_assignment f ON f.employee_id = a.employee_id
  WHERE a.is_active = false
    AND a.effective_from < f.effective_from
    AND a.effective_to = f.effective_from
  ORDER BY a.employee_id, a.effective_from DESC, a.created_at DESC, a.id DESC
)
UPDATE assignments a
SET is_active = true,
    effective_to = predecessor.next_effective_from - 1,
    updated_at = now()
FROM predecessor
WHERE a.id = predecessor.id;

ALTER TABLE assignments
  DROP CONSTRAINT IF EXISTS assignments_no_overlapping_effective_ranges;

ALTER TABLE assignments
  ADD CONSTRAINT assignments_no_overlapping_effective_ranges
  EXCLUDE USING gist (
    employee_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
  WHERE (is_active = true);

CREATE INDEX IF NOT EXISTS idx_assignments_employee_effective_range
  ON assignments (employee_id, effective_from, effective_to)
  WHERE is_active = true;

COMMENT ON COLUMN assignments.is_active IS
  'Whether the assignment record is enabled. Current, scheduled, and ended historical records may remain enabled; effective dates determine applicability.';

COMMIT;
