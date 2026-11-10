-- Memorandum official signatories reuse docutracker_official_signatories.
-- Existing rows, dates, and snapshots are left in place. This only widens
-- the role check so the three memorandum roles can be configured.

BEGIN;

ALTER TABLE docutracker_official_signatories
  DROP CONSTRAINT IF EXISTS docutracker_official_signatories_role_check;

ALTER TABLE docutracker_official_signatories
  ADD CONSTRAINT docutracker_official_signatories_role_check
  CHECK (role_key IN (
    'leave_credit_certifier',
    'dtr_office_hours_verifier',
    'dtr_hr_officer',
    'memo_prepared_by',
    'memo_noted_by',
    'memo_approved_by'
  ));

COMMIT;
