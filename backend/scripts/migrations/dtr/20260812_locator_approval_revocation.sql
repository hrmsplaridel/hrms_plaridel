BEGIN;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS revoked_by UUID
    REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS revocation_reason TEXT,
  ADD COLUMN IF NOT EXISTS month_end_reconciliation_required BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS month_end_reconciled_at TIMESTAMPTZ;

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS locator_slips_status_check;
ALTER TABLE locator_slips
  ADD CONSTRAINT locator_slips_status_check CHECK (
    status IN (
      'pending',
      'pending_department_head',
      'pending_hr',
      'returned_for_correction',
      'approved',
      'revoked',
      'rejected_by_department_head',
      'rejected_by_hr',
      'cancelled'
    )
  );

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS chk_locator_revocation_audit;
ALTER TABLE locator_slips
  ADD CONSTRAINT chk_locator_revocation_audit CHECK (
    status <> 'revoked'
    OR (
      revoked_by IS NOT NULL
      AND revoked_at IS NOT NULL
      AND revocation_reason IS NOT NULL
      AND char_length(btrim(revocation_reason)) BETWEEN 10 AND 1000
    )
  );

COMMENT ON COLUMN locator_slips.revocation_reason IS
  'Required HR/Admin justification for revoking an approved locator.';
COMMENT ON COLUMN locator_slips.month_end_reconciliation_required IS
  'True when revocation changed a month that already has a posted DTR deduction.';

COMMIT;
