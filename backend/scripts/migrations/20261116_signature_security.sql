-- Keys are configured separately. Run the encryption/backfill script after this migration.
BEGIN;
ALTER TABLE docutracker_signature_assets
  DROP CONSTRAINT IF EXISTS docutracker_signature_assets_image_bytes_check;
ALTER TABLE docutracker_signature_assets
  ADD CONSTRAINT docutracker_signature_assets_image_bytes_check
  CHECK (octet_length(image_bytes) BETWEEN 1 AND 2098176);

CREATE TABLE IF NOT EXISTS signature_integrity_receipts (
  subject_key TEXT PRIMARY KEY CHECK (subject_key ~ '^[a-f0-9]{64}$'),
  sealed_manifest JSONB NOT NULL CHECK (jsonb_typeof(sealed_manifest)='object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION prevent_signature_receipt_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Signature integrity receipts are append-only';
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS signature_receipts_immutable ON signature_integrity_receipts;
CREATE TRIGGER signature_receipts_immutable BEFORE UPDATE OR DELETE ON signature_integrity_receipts
  FOR EACH ROW EXECUTE FUNCTION prevent_signature_receipt_mutation();

CREATE TABLE IF NOT EXISTS signature_authorization_uses (
  authorization_id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMIT;
