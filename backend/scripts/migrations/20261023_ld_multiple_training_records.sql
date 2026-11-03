-- Explicit upgrade for the multi-training L&D flow introduced by the merge.
-- Retains existing records and replaces employee uniqueness with a lookup index.
BEGIN;

ALTER TABLE public.ld_training_requirement_records
  DROP CONSTRAINT IF EXISTS uq_ld_training_requirement_employee;

CREATE INDEX IF NOT EXISTS idx_ld_training_requirement_employee
  ON public.ld_training_requirement_records (employee_id, created_at DESC);

COMMIT;
