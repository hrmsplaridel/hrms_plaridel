-- Add optional fields without changing existing locator types or requests.
BEGIN;
ALTER TABLE locator_request_types
  ADD COLUMN IF NOT EXISTS employee_detail_schema JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS employee_detail_schema_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS additional_details JSONB NOT NULL DEFAULT '{}'::jsonb;
COMMIT;
