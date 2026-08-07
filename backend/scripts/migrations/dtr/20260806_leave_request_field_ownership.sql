-- Separate employee-editable leave details from official and HR-owned fields.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260806_leave_request_field_ownership.sql

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS employee_official_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS recommendation_remarks TEXT,
  ADD COLUMN IF NOT EXISTS disapproval_reason TEXT;

ALTER TABLE leave_requests
  DROP CONSTRAINT IF EXISTS chk_leave_employee_official_snapshot_object;

ALTER TABLE leave_requests
  ADD CONSTRAINT chk_leave_employee_official_snapshot_object
  CHECK (jsonb_typeof(employee_official_snapshot) = 'object');

-- Build a trusted snapshot from server records as of the latest filing event.
WITH filing_context AS (
  SELECT lr.id,
         COALESCE(
           (
             SELECT h.acted_at::date
             FROM leave_request_history h
             WHERE h.leave_request_id = lr.id
               AND h.action IN ('submitted', 'resubmitted')
             ORDER BY h.acted_at DESC
             LIMIT 1
           ),
           lr.created_at::date
         ) AS filing_date
  FROM leave_requests lr
)
UPDATE leave_requests lr
SET employee_official_snapshot = jsonb_strip_nulls(
  jsonb_build_object(
    'employee_name', u.full_name,
    'office_department', (
      SELECT d.name
      FROM assignments a
      LEFT JOIN departments d ON d.id = a.department_id
      WHERE a.employee_id = u.id
        AND (a.effective_from IS NULL OR a.effective_from <= fc.filing_date)
        AND (a.effective_to IS NULL OR a.effective_to >= fc.filing_date)
      ORDER BY a.effective_from DESC NULLS LAST,
               a.created_at DESC NULLS LAST,
               a.id DESC
      LIMIT 1
    ),
    'position_title', (
      SELECT p.name
      FROM assignments a
      LEFT JOIN positions p ON p.id = a.position_id
      WHERE a.employee_id = u.id
        AND (a.effective_from IS NULL OR a.effective_from <= fc.filing_date)
        AND (a.effective_to IS NULL OR a.effective_to >= fc.filing_date)
      ORDER BY a.effective_from DESC NULLS LAST,
               a.created_at DESC NULLS LAST,
               a.id DESC
      LIMIT 1
    ),
    'salary', CASE
      WHEN replace(trim(COALESCE(u.salary_grade, '')), ',', '')
           ~ '^[0-9]+(\.[0-9]+)?$'
      THEN replace(trim(u.salary_grade), ',', '')::numeric
      ELSE NULL
    END,
    'date_filed', to_char(fc.filing_date, 'YYYY-MM-DD')
  )
)
FROM users u, filing_context fc
WHERE lr.id = fc.id
  AND u.id = COALESCE(lr.user_id, lr.employee_id)
  AND lr.employee_official_snapshot = '{}'::jsonb;

-- Rejected requests already have an authoritative reviewer_remarks value.
UPDATE leave_requests
SET disapproval_reason = COALESCE(
  disapproval_reason,
  NULLIF(trim(reviewer_remarks), '')
)
WHERE status IN ('rejected', 'rejected_by_hr');

-- Remove known official, workflow, attachment, and HR-only values that older
-- clients could place inside employee-controlled JSON.
UPDATE leave_requests
SET details = COALESCE(details, '{}'::jsonb) - ARRAY[
  'id',
  'user_id',
  'userId',
  'employee_id',
  'employeeId',
  'employee_name',
  'employeeName',
  'office_department',
  'officeDepartment',
  'position_title',
  'positionTitle',
  'salary',
  'salary_grade',
  'salaryGrade',
  'date_filed',
  'dateFiled',
  'status',
  'working_days_applied',
  'workingDaysApplied',
  'total_days',
  'number_of_days',
  'reviewer_id',
  'reviewerId',
  'reviewer_name',
  'reviewerName',
  'reviewer_role',
  'reviewerRole',
  'reviewer_title',
  'reviewerTitle',
  'reviewed_at',
  'reviewedAt',
  'hr_remarks',
  'hrRemarks',
  'recommendation_remarks',
  'recommendationRemarks',
  'disapproval_reason',
  'disapprovalReason',
  'approved_days_with_pay',
  'approvedDaysWithPay',
  'approved_days_without_pay',
  'approvedDaysWithoutPay',
  'approved_other_details',
  'approvedOtherDetails',
  'approved_by',
  'approved_at',
  'review_department_id',
  'assigned_department_head_id',
  'department_head_reviewer_id',
  'departmentHeadReviewerId',
  'department_head_reviewer_name',
  'departmentHeadReviewerName',
  'department_head_reviewed_at',
  'departmentHeadReviewedAt',
  'department_head_remarks',
  'departmentHeadRemarks',
  'department_head_action',
  'departmentHeadAction',
  'attachment_name',
  'attachmentName',
  'attachment_path',
  'attachmentPath',
  'attachment_mime_type',
  'attachment_uploaded_at',
  'created_at',
  'updated_at'
]::text[];
