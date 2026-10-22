BEGIN;
ALTER TABLE locator_request_types
 ADD COLUMN IF NOT EXISTS approval_route TEXT NOT NULL DEFAULT 'hr',
 ADD COLUMN IF NOT EXISTS mayor_employment_types TEXT[];
ALTER TABLE locator_request_types DROP CONSTRAINT IF EXISTS chk_locator_approval_route;
ALTER TABLE locator_request_types ADD CONSTRAINT chk_locator_approval_route
 CHECK (approval_route IN ('hr','mayor','mayor_direct') AND (approval_route='hr' OR NOT auto_approve_admin));
ALTER TABLE locator_slips
 ADD COLUMN IF NOT EXISTS final_review_route TEXT NOT NULL DEFAULT 'hr',
 ADD COLUMN IF NOT EXISTS final_reviewer_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE locator_slips DROP CONSTRAINT IF EXISTS locator_slips_status_check;
ALTER TABLE locator_slips ADD CONSTRAINT locator_slips_status_check CHECK
 (status IN ('pending','pending_department_head','pending_hr','pending_mayor','returned_for_correction','approved','revoked','rejected_by_department_head','rejected_by_hr','cancelled'));
COMMIT;
