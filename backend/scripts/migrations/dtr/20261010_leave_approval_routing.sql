-- Combined unreleased routing migration: department approval completes the
-- Mayor route, and the Mayor signs the printed form manually.
BEGIN;
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS approval_route TEXT NOT NULL DEFAULT 'hr' CHECK(approval_route IN ('hr','mayor'));
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS mayor_employment_types TEXT[];
ALTER TABLE leave_types DROP CONSTRAINT IF EXISTS chk_leave_mayor_employment_types;
ALTER TABLE leave_types ADD CONSTRAINT chk_leave_mayor_employment_types CHECK(mayor_employment_types IS NULL OR
 (cardinality(mayor_employment_types)>0 AND array_position(mayor_employment_types,NULL) IS NULL AND
 mayor_employment_types <@ ARRAY['permanent','temporary','casual','contractual','coterminous','job_order','contract_of_service','regular']::text[]));
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS final_review_route TEXT NOT NULL DEFAULT 'hr' CHECK(final_review_route IN ('hr','mayor'));
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS final_reviewer_user_id UUID REFERENCES users(id);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS routing_employment_type TEXT;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_status_check;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS chk_leave_requests_status;
ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_status_check CHECK(status IN
 ('draft','pending','pending_department_head','pending_hr','pending_mayor','rejected_by_department_head','rejected_by_hr','returned','approved','rejected','cancelled'));
CREATE OR REPLACE FUNCTION snapshot_leave_approval_route() RETURNS trigger AS $$
DECLARE rule leave_types%ROWTYPE; emp_type TEXT; mayor_id UUID; recapture BOOLEAN;
BEGIN
 recapture:=TG_OP='INSERT';
 IF TG_OP='UPDATE' THEN recapture:=OLD.status IN ('draft','returned','rejected_by_department_head','rejected_by_hr') AND NEW.status IN ('pending','pending_department_head','pending_hr'); END IF;
 IF recapture THEN
  SELECT * INTO rule FROM leave_types WHERE id=NEW.leave_type_id;
  SELECT employment_type INTO emp_type FROM users WHERE id=COALESCE(NEW.employee_id,NEW.user_id);
  NEW.routing_employment_type:=emp_type;
  NEW.final_review_route:='hr'; NEW.final_reviewer_user_id:=NULL;
  IF rule.approval_route='mayor' AND (rule.mayor_employment_types IS NULL OR emp_type=ANY(rule.mayor_employment_types)) THEN
   SELECT id INTO mayor_id FROM users WHERE role='mayor' AND is_active=true AND COALESCE(employment_status,'active')='active'
    AND (date_hired IS NULL OR date_hired<=(now() AT TIME ZONE 'Asia/Manila')::date)
    AND (separation_date IS NULL OR separation_date>=(now() AT TIME ZONE 'Asia/Manila')::date) ORDER BY created_at DESC LIMIT 1;
   NEW.final_review_route:='mayor'; NEW.final_reviewer_user_id:=mayor_id;
  END IF;
 END IF;
 IF NEW.final_review_route='mayor' AND NEW.status IN ('pending_department_head','pending_hr','pending_mayor') THEN
  IF NEW.final_reviewer_user_id IS NULL OR NEW.final_reviewer_user_id=COALESCE(NEW.employee_id,NEW.user_id) THEN
   RAISE EXCEPTION 'Approval routing: an eligible active Mayor is required.';
  END IF;
  IF NEW.assigned_department_head_id IS NULL OR NEW.assigned_department_head_id=COALESCE(NEW.employee_id,NEW.user_id) THEN
   RAISE EXCEPTION 'Approval routing: a different department reviewer is required.';
  END IF;
 END IF;
 IF NEW.final_review_route='mayor' AND NEW.status IN ('pending_hr','pending_mayor') THEN
  RAISE EXCEPTION 'Approval routing: manual Mayor signing requires department approval, without a final electronic reviewer.';
 END IF;
 IF NEW.final_review_route='mayor' AND NEW.status='rejected_by_hr' THEN NEW.status:='rejected'; END IF;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_leave_approval_route ON leave_requests;
CREATE TRIGGER trg_snapshot_leave_approval_route BEFORE INSERT OR UPDATE OF status,leave_type_id ON leave_requests
 FOR EACH ROW EXECUTE FUNCTION snapshot_leave_approval_route();
CREATE OR REPLACE FUNCTION snapshot_leave_print_template() RETURNS trigger AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  SELECT print_template_version_id INTO NEW.print_template_version_id FROM leave_types WHERE id=NEW.leave_type_id;
 ELSIF OLD.status='draft' OR (NEW.status IN ('pending','pending_department_head','pending_hr','pending_mayor') AND
  OLD.status IN ('returned','returned_by_department_head')) THEN
  SELECT print_template_version_id INTO NEW.print_template_version_id FROM leave_types WHERE id=NEW.leave_type_id;
 END IF;
 RETURN NEW;
END;$$ LANGUAGE plpgsql;
-- Compatibility with local databases that installed the unreleased electronic
-- Mayor workflow. Complete accounting through the department approval API.
UPDATE leave_requests SET status='pending_department_head'
WHERE final_review_route='mayor' AND status='pending_mayor';
COMMIT;
