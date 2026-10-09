-- Defaults only: HR can deliberately override credit eligibility or filing lists later.
-- First application excludes existing JO/COS accounts from future credit accrual.
-- Balances, ledger entries, leave requests and custom leave rules are preserved.
BEGIN;

ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS eligible_employment_types TEXT[];
ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_leave_type_employment_eligibility;
ALTER TABLE leave_types ADD CONSTRAINT chk_leave_type_employment_eligibility CHECK (
  eligible_employment_types IS NULL OR (
    cardinality(eligible_employment_types) > 0
    AND array_position(eligible_employment_types, NULL) IS NULL
    AND eligible_employment_types <@ ARRAY['permanent','temporary','casual',
      'contractual','coterminous','job_order','contract_of_service','regular']::text[]
  )
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='users'::regclass
    AND tgname='trg_users_jo_cos_credit_default' AND NOT tgisinternal) THEN
    UPDATE users SET leave_credit_eligible=false, leave_credit_eligible_until=NULL, updated_at=now()
      WHERE employment_type IN ('job_order','contract_of_service');
    UPDATE leave_types SET eligible_employment_types=ARRAY[
      'permanent','temporary','casual','contractual','coterminous','regular']::text[], updated_at=now()
      WHERE is_system=true;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION apply_jo_cos_credit_default() RETURNS trigger AS $$
BEGIN
  IF NEW.employment_type IN ('job_order','contract_of_service')
    AND (TG_OP='INSERT' OR NEW.employment_type IS DISTINCT FROM OLD.employment_type) THEN
    NEW.leave_credit_eligible := false;
    NEW.leave_credit_eligible_until := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_users_jo_cos_credit_default ON users;
CREATE TRIGGER trg_users_jo_cos_credit_default BEFORE INSERT OR UPDATE OF employment_type ON users
  FOR EACH ROW EXECUTE FUNCTION apply_jo_cos_credit_default();
COMMIT;
