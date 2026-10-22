-- Preserve existing leave filing permissions; Employee only is an explicit choice.
BEGIN;
ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS admin_can_file BOOLEAN NOT NULL DEFAULT true;
COMMIT;
