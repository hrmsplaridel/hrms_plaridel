-- Existing locator types remain employee-only with normal approval.
BEGIN;
ALTER TABLE locator_request_types
  ADD COLUMN IF NOT EXISTS filing_access TEXT NOT NULL DEFAULT 'employee',
  ADD COLUMN IF NOT EXISTS auto_approve_admin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE locator_request_types ALTER COLUMN filing_access SET DEFAULT 'employee';
ALTER TABLE locator_request_types DROP CONSTRAINT IF EXISTS chk_locator_filing_access;
ALTER TABLE locator_request_types ADD CONSTRAINT chk_locator_filing_access
  CHECK (filing_access IN ('employee','admin','both') AND (NOT auto_approve_admin OR filing_access <> 'employee'));
COMMIT;
