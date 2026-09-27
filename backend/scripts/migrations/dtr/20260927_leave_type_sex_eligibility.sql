-- Keep sex-based leave eligibility available before the API starts on both
-- upgraded and fresh databases.
-- Run: psql -v ON_ERROR_STOP=1 -d hrms_plaridel -f backend/scripts/migrations/dtr/20260927_leave_type_sex_eligibility.sql

BEGIN;

ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS sex_eligibility TEXT;

UPDATE leave_types
SET sex_eligibility = CASE
  WHEN name IN ('maternityLeave', 'tenDayVawcLeave', 'specialLeaveBenefitsForWomen') THEN 'female'
  WHEN name = 'paternityLeave' THEN 'male'
  WHEN name IN (
    'vacationLeave',
    'mandatoryForcedLeave',
    'sickLeave',
    'specialPrivilegeLeave',
    'soloParentLeave',
    'studyLeave',
    'rehabilitationPrivilege',
    'specialEmergencyCalamityLeave',
    'adoptionLeave',
    'others'
  ) THEN 'any'
  WHEN sex_eligibility IN ('any', 'female', 'male') THEN sex_eligibility
  ELSE 'any'
END,
updated_at = now()
WHERE (
    name IN ('maternityLeave', 'tenDayVawcLeave', 'specialLeaveBenefitsForWomen')
    AND sex_eligibility IS DISTINCT FROM 'female'
  )
   OR (name = 'paternityLeave' AND sex_eligibility IS DISTINCT FROM 'male')
   OR (
     name IN (
     'vacationLeave',
     'mandatoryForcedLeave',
     'sickLeave',
     'specialPrivilegeLeave',
     'soloParentLeave',
     'studyLeave',
     'rehabilitationPrivilege',
     'specialEmergencyCalamityLeave',
     'adoptionLeave',
     'others'
     )
     AND sex_eligibility IS DISTINCT FROM 'any'
   )
   OR (
     name NOT IN (
       'vacationLeave',
       'mandatoryForcedLeave',
       'sickLeave',
       'maternityLeave',
       'paternityLeave',
       'specialPrivilegeLeave',
       'soloParentLeave',
       'studyLeave',
       'tenDayVawcLeave',
       'rehabilitationPrivilege',
       'specialLeaveBenefitsForWomen',
       'specialEmergencyCalamityLeave',
       'adoptionLeave',
       'others'
     )
     AND (
       sex_eligibility IS NULL
       OR sex_eligibility NOT IN ('any', 'female', 'male')
     )
   );

ALTER TABLE leave_types
  ALTER COLUMN sex_eligibility SET DEFAULT 'any',
  ALTER COLUMN sex_eligibility SET NOT NULL,
  DROP CONSTRAINT IF EXISTS chk_leave_type_sex_eligibility;

ALTER TABLE leave_types
  ADD CONSTRAINT chk_leave_type_sex_eligibility
    CHECK (sex_eligibility IN ('any', 'female', 'male'));

COMMIT;
