BEGIN;

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS locator_slips_status_check;

ALTER TABLE locator_slips
  ADD CONSTRAINT locator_slips_status_check
  CHECK (status IN (
    'pending',
    'pending_department_head',
    'pending_hr',
    'returned_for_correction',
    'approved',
    'rejected_by_department_head',
    'rejected_by_hr',
    'cancelled'
  ));

COMMIT;
