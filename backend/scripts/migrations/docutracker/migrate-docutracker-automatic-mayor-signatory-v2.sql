BEGIN;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS approving_authority_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_approving_authority_snapshot_object;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_approving_authority_snapshot_object
  CHECK (jsonb_typeof(approving_authority_snapshot) = 'object');

DELETE FROM docutracker_official_signatories
WHERE role_key = 'leave_approving_authority';

ALTER TABLE docutracker_official_signatories
  DROP CONSTRAINT IF EXISTS docutracker_official_signatories_role_check;

ALTER TABLE docutracker_official_signatories
  ADD CONSTRAINT docutracker_official_signatories_role_check
  CHECK (role_key IN ('leave_credit_certifier'));

COMMIT;
