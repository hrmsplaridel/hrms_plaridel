-- DocuTracker: stop role-wide `view` on '*' from implying org-wide document list access.
-- Document visibility is enforced by relationship rules in docutrackerWorkflowService.js.
-- Run once on existing databases after deploying the service change.
--
--   psql -d YOUR_DB -f backend/scripts/docutracker-fix-view-list-scope.sql

UPDATE docutracker_permissions
SET granted = false,
    updated_at = NOW()
WHERE user_id IS NULL
  AND action = 'view'
  AND document_type = '*'
  AND role_id IN ('employee', 'hr', 'supervisor', 'hr_staff', 'dept_head');
