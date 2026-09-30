-- DocuTracker: Mayor's Memorandums may only be prepared (created/submitted)
-- by users an admin has explicitly authorized, e.g. Mayor's Office staff.
--
-- Role baselines grant create/submit on '*'. These role rows for the specific
-- memo type outrank that wildcard (permissionPriority 200 vs 100). An admin
-- authorizes a preparer with user-specific memo create_draft/submit grants in
-- System Access (400 beats 200).
--
-- Final approval (issuing the Memo) is not a permission row: the workflow
-- service only lets the active Mayor approve the last Memo step, and only
-- after signing. Preparers therefore cannot issue a Memo themselves.
--
-- Idempotent.

INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
VALUES
  ('employee',   NULL::uuid, 'memo', 'create_draft', false),
  ('employee',   NULL::uuid, 'memo', 'submit',       false),
  ('hr',         NULL::uuid, 'memo', 'create_draft', false),
  ('hr',         NULL::uuid, 'memo', 'submit',       false),
  ('supervisor', NULL::uuid, 'memo', 'create_draft', false),
  ('supervisor', NULL::uuid, 'memo', 'submit',       false)
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();
