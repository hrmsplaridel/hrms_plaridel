BEGIN;

ALTER TABLE docutracker_official_signatories
  DROP CONSTRAINT IF EXISTS docutracker_official_signatories_role_check;
ALTER TABLE docutracker_official_signatories
  ADD CONSTRAINT docutracker_official_signatories_role_check
  CHECK (role_key IN (
    'leave_credit_certifier', 'dtr_office_hours_verifier', 'dtr_hr_officer'
  ));

COMMIT;
