-- DocuTracker: printed signer identity frozen at signing time.
--
-- A signed builder field already stores who signed (signed_by), when
-- (signed_at) and the printed name (signer_name_snapshot). This adds the
-- printed position/title and the signer's role at that moment, so an official
-- signed document keeps printing the identity it was signed with after the
-- employee later changes position, name or status, or a new Mayor takes office.
--
-- No backfill: fields signed before this migration have no recorded position
-- or role, and none is invented for them.
--
-- Idempotent.

BEGIN;

ALTER TABLE docutracker_signature_fields
  ADD COLUMN IF NOT EXISTS signer_position_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS signer_role_snapshot TEXT;

ALTER TABLE docutracker_signature_fields
  DROP CONSTRAINT IF EXISTS docutracker_signature_fields_identity_snapshot_check_v1;

ALTER TABLE docutracker_signature_fields
  ADD CONSTRAINT docutracker_signature_fields_identity_snapshot_check_v1
  CHECK (
    (signer_position_snapshot IS NULL OR btrim(signer_position_snapshot) <> '')
    AND (signer_role_snapshot IS NULL OR btrim(signer_role_snapshot) <> '')
    AND (signed_at IS NOT NULL
      OR (signer_position_snapshot IS NULL AND signer_role_snapshot IS NULL))
  ) NOT VALID;

ALTER TABLE docutracker_signature_fields
  VALIDATE CONSTRAINT docutracker_signature_fields_identity_snapshot_check_v1;

COMMIT;
