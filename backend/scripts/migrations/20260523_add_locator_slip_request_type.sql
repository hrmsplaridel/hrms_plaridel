ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'locator';

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS locator_slips_request_type_check;

ALTER TABLE locator_slips
  ADD CONSTRAINT locator_slips_request_type_check
  CHECK (request_type IN ('locator', 'pass_slip', 'work_from_home'));

CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
  ON locator_slips(request_type);

COMMENT ON COLUMN locator_slips.request_type IS
  'Fixed request type for locator workflow: locator, pass_slip, or work_from_home.';
