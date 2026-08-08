-- Add schema-driven employee fields for custom leave types and preserve the
-- exact schema used by each filed request.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260807_dynamic_leave_type_fields.sql

ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS employee_detail_schema JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS employee_detail_schema_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE leave_types
  DROP CONSTRAINT IF EXISTS chk_leave_type_employee_detail_schema_array;

ALTER TABLE leave_types
  ADD CONSTRAINT chk_leave_type_employee_detail_schema_array
  CHECK (jsonb_typeof(employee_detail_schema) = 'array');

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_employee_detail_schema_snapshot_array;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_employee_detail_schema_snapshot_array
  CHECK (jsonb_typeof(employee_detail_schema_snapshot) = 'array');

COMMENT ON COLUMN leave_types.employee_detail_schema IS
  'Validated employee-editable custom field definitions for this leave type.';

COMMENT ON COLUMN leave_requests.employee_detail_schema_snapshot IS
  'Immutable-at-filing copy of custom field definitions used to label historical answers.';
