-- Repair legacy sort orders and enforce locator-type rule integrity.
-- Run: psql -v ON_ERROR_STOP=1 -d hrms_plaridel -f backend/scripts/migrations/dtr/20260927_locator_type_rule_constraints.sql

BEGIN;

UPDATE locator_request_types
SET sort_order = 0,
    updated_at = now()
WHERE sort_order < 0;

ALTER TABLE locator_request_types
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_sort_order_nonnegative;

ALTER TABLE locator_request_types
  ADD CONSTRAINT chk_locator_request_types_sort_order_nonnegative
  CHECK (sort_order >= 0);

COMMIT;
