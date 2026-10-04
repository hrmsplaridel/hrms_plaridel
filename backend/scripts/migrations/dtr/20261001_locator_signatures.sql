-- Apply before deploying the Locator signature endpoints. Requires the existing
-- DocuTracker signature-assets migration; this does not modify Leave signatures.
BEGIN;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS print_signatories JSONB,
  ADD COLUMN IF NOT EXISTS signature_revision INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS docutracker_locator_signatures (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  locator_slip_id UUID NOT NULL REFERENCES locator_slips(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL,
  slot_key TEXT NOT NULL CHECK (slot_key IN ('applicant', 'department_head', 'hr_approver')),
  signature_asset_id UUID NOT NULL REFERENCES docutracker_signature_assets(id) ON DELETE RESTRICT,
  signed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  signer_name_snapshot TEXT NOT NULL,
  signed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (locator_slip_id, revision, slot_key)
);

-- Keep previous signatures for audit, but never reuse them on changed content.
CREATE OR REPLACE FUNCTION invalidate_locator_signatures() RETURNS trigger AS $$
BEGIN
  IF ROW(NEW.slip_date, NEW.office, NEW.reason, NEW.request_type,
         NEW.am_in, NEW.am_out, NEW.pm_in, NEW.pm_out, NEW.employee_id,
         NEW.department_id, NEW.attachment_path, NEW.attachment_uploaded_at)
     IS DISTINCT FROM
     ROW(OLD.slip_date, OLD.office, OLD.reason, OLD.request_type,
         OLD.am_in, OLD.am_out, OLD.pm_in, OLD.pm_out, OLD.employee_id,
         OLD.department_id, OLD.attachment_path, OLD.attachment_uploaded_at)
     OR (NEW.status IS DISTINCT FROM OLD.status AND
         NEW.status IN ('returned_for_correction', 'returned', 'cancelled', 'revoked'))
  THEN
    NEW.signature_revision := OLD.signature_revision + 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS locator_signature_revision ON locator_slips;
CREATE TRIGGER locator_signature_revision BEFORE UPDATE ON locator_slips
FOR EACH ROW EXECUTE FUNCTION invalidate_locator_signatures();

COMMIT;
