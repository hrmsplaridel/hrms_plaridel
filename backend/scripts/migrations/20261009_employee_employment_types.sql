-- Municipal employment types. Contractual appointment and COS remain distinct.
-- Preserve legacy regular rows; HR must explicitly classify them before conversion.
-- Idempotent; changes constraints only, not employee records or leave eligibility.
BEGIN;

DO $$
DECLARE existing_constraint record;
BEGIN
  FOR existing_constraint IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'users'::regclass AND contype = 'c'
      AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
        WHERE attrelid = 'users'::regclass AND attname = 'employment_type')]::smallint[]
  LOOP
    EXECUTE format('ALTER TABLE users DROP CONSTRAINT %I', existing_constraint.conname);
  END LOOP;
END $$;

ALTER TABLE users ADD CONSTRAINT users_employment_type_check
  CHECK (employment_type IN (
    'permanent', 'temporary', 'casual', 'contractual', 'coterminous',
    'job_order', 'contract_of_service', 'regular'
  ));

COMMIT;
