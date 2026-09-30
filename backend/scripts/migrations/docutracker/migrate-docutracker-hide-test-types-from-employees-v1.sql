-- DocuTracker: stop normal employees from creating the built-in test types.
--
-- The employee role is granted create on '*'. A role row for a specific
-- document_type outranks the wildcard (permissionPriority 200 vs 100), so these
-- deny rows hide Memo and Purchase Request from employees while keeping the
-- workflows and existing documents intact. Admins are unaffected.
--
-- Idempotent.

INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
VALUES
  ('employee', NULL::uuid, 'memo',            'create_draft', false),
  ('employee', NULL::uuid, 'purchaseRequest', 'create_draft', false)
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();
