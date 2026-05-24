-- DocuTracker permission baseline seed/upsert
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/seed-docutracker-permission-baseline.sql
--
-- Notes:
-- - This script defines baseline ROLE permissions using document_type='*'.
-- - Explicit user-level permissions in the UI can still override these.
-- - role_id values must exist in docutracker_roles (see production hardening).
--   Legacy JWT aliases (hr_staff, dept_head) are mapped in app/SQL via docutracker_role_aliases;
--   do not insert non-canonical role_id rows here or the role FK will reject them.

WITH baseline(role_id, document_type, action, granted) AS (
  VALUES
    -- Employee baseline: can create/submit/view/download their workflow-relevant docs.
    ('employee',  '*', 'view',     true),
    ('employee',  '*', 'create',   true),
    ('employee',  '*', 'submit',   true),
    ('employee',  '*', 'download', true),
    ('employee',  '*', 'edit',     false),
    ('employee',  '*', 'delete',   false),
    ('employee',  '*', 'forward',  false),
    ('employee',  '*', 'approve',  false),
    ('employee',  '*', 'reject',   false),
    ('employee',  '*', 'return',   false),

    -- HR baseline: review-capable.
    ('hr',        '*', 'view',     true),
    ('hr',        '*', 'create',   true),
    ('hr',        '*', 'submit',   true),
    ('hr',        '*', 'download', true),
    ('hr',        '*', 'edit',     true),
    ('hr',        '*', 'delete',   false),
    ('hr',        '*', 'forward',  true),
    ('hr',        '*', 'approve',  true),
    ('hr',        '*', 'reject',   true),
    ('hr',        '*', 'return',   true),

    -- Supervisor baseline: review-capable.
    ('supervisor','*', 'view',     true),
    ('supervisor','*', 'create',   true),
    ('supervisor','*', 'submit',   true),
    ('supervisor','*', 'download', true),
    ('supervisor','*', 'edit',     true),
    ('supervisor','*', 'delete',   false),
    ('supervisor','*', 'forward',  true),
    ('supervisor','*', 'approve',  true),
    ('supervisor','*', 'reject',   true),
    ('supervisor','*', 'return',   true),

    -- Admin explicit baseline (admin already has service-level override).
    ('admin',     '*', 'view',     true),
    ('admin',     '*', 'create',   true),
    ('admin',     '*', 'submit',   true),
    ('admin',     '*', 'download', true),
    ('admin',     '*', 'edit',     true),
    ('admin',     '*', 'delete',   true),
    ('admin',     '*', 'forward',  true),
    ('admin',     '*', 'approve',  true),
    ('admin',     '*', 'reject',   true),
    ('admin',     '*', 'return',   true)
)
INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
SELECT
  b.role_id,
  NULL::uuid,
  b.document_type,
  b.action,
  b.granted
FROM baseline b
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();

-- Evidence summary
SELECT
  role_id,
  action,
  document_type,
  granted
FROM docutracker_permissions
WHERE user_id IS NULL
  AND role_id IN ('employee', 'hr', 'supervisor', 'admin')
ORDER BY role_id, document_type, action;
