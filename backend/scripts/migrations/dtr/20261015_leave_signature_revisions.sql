-- Requires the existing Leave routing/print snapshots and DocuTracker Leave signatures.
-- Saved signature images remain reusable. Previous confirmations remain as history.
BEGIN;

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS signature_revision INTEGER NOT NULL DEFAULT 1
    CHECK (signature_revision > 0);
ALTER TABLE docutracker_leave_signatures
  ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0);
ALTER TABLE docutracker_leave_signatures
  DROP CONSTRAINT IF EXISTS docutracker_leave_signatures_request_slot_unique;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'docutracker_leave_signatures'::regclass
      AND conname = 'docutracker_leave_signatures_request_revision_slot_unique'
  ) THEN
    ALTER TABLE docutracker_leave_signatures
      ADD CONSTRAINT docutracker_leave_signatures_request_revision_slot_unique
      UNIQUE (leave_request_id, revision, slot_key);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION invalidate_leave_signatures() RETURNS trigger AS $$
BEGIN
  NEW.signature_revision := OLD.signature_revision;
  IF ROW(NEW.leave_type_id, NEW.start_date, NEW.end_date, NEW.number_of_days,
         NEW.total_days, NEW.reason, NEW.details, NEW.user_id, NEW.employee_id,
         NEW.attachment_name, NEW.attachment_path, NEW.attachment_mime_type,
         NEW.attachment_uploaded_at, NEW.employee_official_snapshot,
         NEW.employee_detail_schema_snapshot, NEW.print_template_version_id,
         NEW.review_department_id, NEW.assigned_department_head_id,
         NEW.final_review_route, NEW.final_reviewer_user_id)
     IS DISTINCT FROM
     ROW(OLD.leave_type_id, OLD.start_date, OLD.end_date, OLD.number_of_days,
         OLD.total_days, OLD.reason, OLD.details, OLD.user_id, OLD.employee_id,
         OLD.attachment_name, OLD.attachment_path, OLD.attachment_mime_type,
         OLD.attachment_uploaded_at, OLD.employee_official_snapshot,
         OLD.employee_detail_schema_snapshot, OLD.print_template_version_id,
         OLD.review_department_id, OLD.assigned_department_head_id,
         OLD.final_review_route, OLD.final_reviewer_user_id)
     OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN
         ('returned', 'rejected', 'rejected_by_department_head', 'rejected_by_hr', 'cancelled'))
     OR (OLD.status IN ('returned', 'rejected', 'rejected_by_department_head', 'rejected_by_hr')
         AND NEW.status IN ('pending', 'pending_department_head', 'pending_hr', 'pending_mayor'))
  THEN
    NEW.signature_revision := OLD.signature_revision + 1;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Run after the routing and printed-template snapshot triggers (alphabetical order).
DROP TRIGGER IF EXISTS zz_leave_signature_revision ON leave_requests;
CREATE TRIGGER zz_leave_signature_revision BEFORE UPDATE ON leave_requests
FOR EACH ROW EXECUTE FUNCTION invalidate_leave_signatures();

COMMIT;
