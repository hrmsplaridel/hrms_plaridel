BEGIN;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS assigned_department_head_id UUID
    REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_locator_slips_assigned_department_head
  ON locator_slips(assigned_department_head_id, status, updated_at DESC);

COMMENT ON COLUMN locator_slips.assigned_department_head_id IS
  'Department head assigned when the locator request is submitted or resubmitted; separate from the reviewer who later acts.';

COMMIT;
