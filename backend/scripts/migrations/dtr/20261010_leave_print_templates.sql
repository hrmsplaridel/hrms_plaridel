BEGIN;
CREATE TABLE IF NOT EXISTS leave_print_template_versions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 leave_type_id UUID NOT NULL REFERENCES leave_types(id) ON DELETE RESTRICT,
 layout TEXT NOT NULL DEFAULT 'csc' CHECK(layout IN ('csc','wellness')),
 background_pdf BYTEA,
 background_name TEXT,
 created_by UUID REFERENCES users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(background_pdf IS NULL OR octet_length(background_pdf) <= 5242880)
);
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS print_template_version_id UUID REFERENCES leave_print_template_versions(id);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS print_template_version_id UUID REFERENCES leave_print_template_versions(id);
INSERT INTO leave_print_template_versions(leave_type_id)
 SELECT id FROM leave_types WHERE print_template_version_id IS NULL;
UPDATE leave_types lt SET print_template_version_id=v.id
 FROM leave_print_template_versions v WHERE v.leave_type_id=lt.id AND lt.print_template_version_id IS NULL;
UPDATE leave_requests lr SET print_template_version_id=lt.print_template_version_id
 FROM leave_types lt WHERE lr.leave_type_id=lt.id AND lr.print_template_version_id IS NULL;
CREATE OR REPLACE FUNCTION initialize_leave_print_template() RETURNS trigger AS $$
DECLARE version_id UUID;
BEGIN
 INSERT INTO leave_print_template_versions(leave_type_id) VALUES(NEW.id) RETURNING id INTO version_id;
 UPDATE leave_types SET print_template_version_id=version_id WHERE id=NEW.id;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_initialize_leave_print_template ON leave_types;
CREATE TRIGGER trg_initialize_leave_print_template AFTER INSERT ON leave_types
 FOR EACH ROW EXECUTE FUNCTION initialize_leave_print_template();
CREATE OR REPLACE FUNCTION snapshot_leave_print_template() RETURNS trigger AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  SELECT print_template_version_id INTO NEW.print_template_version_id FROM leave_types WHERE id=NEW.leave_type_id;
 ELSIF OLD.status='draft' OR (NEW.status IN ('pending','pending_department_head','pending_hr') AND
  OLD.status IN ('returned','returned_by_department_head')) THEN
  SELECT print_template_version_id INTO NEW.print_template_version_id FROM leave_types WHERE id=NEW.leave_type_id;
 END IF;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_leave_print_template ON leave_requests;
CREATE TRIGGER trg_snapshot_leave_print_template BEFORE INSERT OR UPDATE OF status,leave_type_id ON leave_requests
 FOR EACH ROW EXECUTE FUNCTION snapshot_leave_print_template();
COMMIT;
