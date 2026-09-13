BEGIN;

ALTER TABLE docutracker_leave_signatures
  DROP CONSTRAINT IF EXISTS docutracker_leave_signatures_slot_check;

ALTER TABLE docutracker_leave_signatures
  ADD CONSTRAINT docutracker_leave_signatures_slot_check
  CHECK (slot_key IN ('applicant', 'department_head'));

COMMIT;
