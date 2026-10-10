-- Versioned locator letterheads. Existing slips retain the empty/default template.
BEGIN;
CREATE TABLE IF NOT EXISTS locator_print_template_versions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 locator_type_id UUID NOT NULL REFERENCES locator_request_types(id) ON DELETE CASCADE,
 background_pdf BYTEA,
 background_name TEXT,
 created_by UUID REFERENCES users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(background_pdf IS NULL OR octet_length(background_pdf) <= 5242880)
);
ALTER TABLE locator_request_types ADD COLUMN IF NOT EXISTS print_template_version_id UUID REFERENCES locator_print_template_versions(id);
ALTER TABLE locator_slips ADD COLUMN IF NOT EXISTS print_template_version_id UUID REFERENCES locator_print_template_versions(id);
INSERT INTO locator_print_template_versions(locator_type_id)
 SELECT id FROM locator_request_types WHERE print_template_version_id IS NULL;
UPDATE locator_request_types t SET print_template_version_id=v.id
 FROM locator_print_template_versions v WHERE v.locator_type_id=t.id AND t.print_template_version_id IS NULL;
-- Leave existing requests NULL: this means the original/default form and avoids
-- touching their updated_at/signature/audit triggers during installation.
CREATE OR REPLACE FUNCTION initialize_locator_print_template() RETURNS trigger AS $$
DECLARE version_id UUID;
BEGIN
 INSERT INTO locator_print_template_versions(locator_type_id) VALUES(NEW.id) RETURNING id INTO version_id;
 UPDATE locator_request_types SET print_template_version_id=version_id WHERE id=NEW.id;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_initialize_locator_print_template ON locator_request_types;
CREATE TRIGGER trg_initialize_locator_print_template AFTER INSERT ON locator_request_types
 FOR EACH ROW EXECUTE FUNCTION initialize_locator_print_template();
CREATE OR REPLACE FUNCTION snapshot_locator_print_template() RETURNS trigger AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  SELECT print_template_version_id INTO NEW.print_template_version_id FROM locator_request_types WHERE code=NEW.request_type;
 ELSE
  -- Approval, correction and resubmission must keep the original filed form.
  NEW.print_template_version_id:=OLD.print_template_version_id;
 END IF;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_locator_print_template ON locator_slips;
CREATE TRIGGER trg_snapshot_locator_print_template BEFORE INSERT OR UPDATE ON locator_slips
 FOR EACH ROW EXECUTE FUNCTION snapshot_locator_print_template();
COMMIT;
