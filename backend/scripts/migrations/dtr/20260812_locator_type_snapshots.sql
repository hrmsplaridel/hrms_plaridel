BEGIN;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS request_type_label_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_short_label_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_location_label_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_location_hint_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_dtr_slot_label_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_dtr_print_label_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_requires_attachment_snapshot BOOLEAN,
  ADD COLUMN IF NOT EXISTS request_type_coverage_mode_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS request_type_snapshot_at TIMESTAMPTZ;

UPDATE locator_slips AS slip
SET request_type_label_snapshot = COALESCE(
      slip.request_type_label_snapshot,
      locator_type.label
    ),
    request_type_short_label_snapshot = COALESCE(
      slip.request_type_short_label_snapshot,
      locator_type.short_label
    ),
    request_type_location_label_snapshot = COALESCE(
      slip.request_type_location_label_snapshot,
      locator_type.location_label
    ),
    request_type_location_hint_snapshot = COALESCE(
      slip.request_type_location_hint_snapshot,
      locator_type.location_hint
    ),
    request_type_dtr_slot_label_snapshot = COALESCE(
      slip.request_type_dtr_slot_label_snapshot,
      locator_type.dtr_slot_label
    ),
    request_type_dtr_print_label_snapshot = COALESCE(
      slip.request_type_dtr_print_label_snapshot,
      locator_type.dtr_print_label
    ),
    request_type_requires_attachment_snapshot = COALESCE(
      slip.request_type_requires_attachment_snapshot,
      locator_type.requires_attachment
    ),
    request_type_coverage_mode_snapshot = COALESCE(
      slip.request_type_coverage_mode_snapshot,
      locator_type.coverage_mode
    ),
    request_type_snapshot_at = COALESCE(
      slip.request_type_snapshot_at,
      now()
    )
FROM locator_request_types AS locator_type
WHERE locator_type.code = slip.request_type
  AND (
    slip.request_type_label_snapshot IS NULL
    OR slip.request_type_short_label_snapshot IS NULL
    OR slip.request_type_location_label_snapshot IS NULL
    OR slip.request_type_location_hint_snapshot IS NULL
    OR slip.request_type_dtr_slot_label_snapshot IS NULL
    OR slip.request_type_dtr_print_label_snapshot IS NULL
    OR slip.request_type_requires_attachment_snapshot IS NULL
    OR slip.request_type_coverage_mode_snapshot IS NULL
    OR slip.request_type_snapshot_at IS NULL
  );

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS chk_locator_type_coverage_snapshot;
ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS locator_slips_request_type_coverage_mode_snapshot_check;
ALTER TABLE locator_slips
  ADD CONSTRAINT chk_locator_type_coverage_snapshot CHECK (
    request_type_coverage_mode_snapshot IS NULL
    OR request_type_coverage_mode_snapshot IN ('manual', 'wfh')
  );

COMMENT ON COLUMN locator_slips.request_type_label_snapshot IS
  'Immutable locator type label captured when the request was first submitted.';
COMMENT ON COLUMN locator_slips.request_type_requires_attachment_snapshot IS
  'Immutable attachment requirement captured when the request was first submitted.';
COMMENT ON COLUMN locator_slips.request_type_coverage_mode_snapshot IS
  'Immutable DTR coverage mode captured when the request was first submitted.';

COMMIT;
