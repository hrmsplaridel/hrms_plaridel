BEGIN;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS is_retroactive_correction BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS retroactive_correction_reason TEXT,
  ADD COLUMN IF NOT EXISTS retroactive_corrected_by UUID
    REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS retroactive_corrected_at TIMESTAMPTZ;

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS chk_locator_planned_time_pair;

ALTER TABLE locator_slips
  DROP COLUMN IF EXISTS planned_start_time,
  DROP COLUMN IF EXISTS planned_end_time;

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS chk_locator_correction_audit;
ALTER TABLE locator_slips
  ADD CONSTRAINT chk_locator_correction_audit CHECK (
    is_retroactive_correction = false
    OR (
      retroactive_correction_reason IS NOT NULL
      AND char_length(btrim(retroactive_correction_reason)) BETWEEN 10 AND 1000
      AND retroactive_corrected_by IS NOT NULL
      AND retroactive_corrected_at IS NOT NULL
    )
  );

COMMENT ON COLUMN locator_slips.retroactive_correction_reason IS
  'Required HR/Admin justification when recording a locator for a past date.';

COMMIT;
