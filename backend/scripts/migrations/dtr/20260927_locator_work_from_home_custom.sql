-- Convert the formerly seeded Work From Home row into an ordinary locator type.
-- Run: psql -v ON_ERROR_STOP=1 -d hrms_plaridel -f backend/scripts/migrations/dtr/20260927_locator_work_from_home_custom.sql

BEGIN;

UPDATE locator_request_types
SET is_system = false,
    updated_at = now()
WHERE code = 'work_from_home'
  AND is_system = true;

COMMIT;
