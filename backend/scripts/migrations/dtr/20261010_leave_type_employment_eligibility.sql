-- NULL preserves existing filing behavior. A configured list restricts filing
-- to matching employment types. This does not change credits or request history.
BEGIN;
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS eligible_employment_types TEXT[];
ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_leave_type_employment_eligibility;
ALTER TABLE leave_types ADD CONSTRAINT chk_leave_type_employment_eligibility CHECK (
  eligible_employment_types IS NULL OR (
    cardinality(eligible_employment_types) > 0
    AND array_position(eligible_employment_types, NULL) IS NULL
    AND eligible_employment_types <@ ARRAY[
      'permanent', 'temporary', 'casual', 'contractual', 'coterminous',
      'job_order', 'contract_of_service', 'regular'
    ]::text[]
  )
);
COMMIT;
