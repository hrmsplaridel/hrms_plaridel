-- DocuTracker: Purchase Requests may only be created and submitted by
-- employees an admin has explicitly authorized.
--
-- Role baselines grant create/submit on '*'. These role rows for the specific
-- purchaseRequest type outrank that wildcard (permissionPriority 200 vs 100),
-- so no non-admin role can create or submit a Purchase Request by default.
--
-- To authorize a person, an admin grants them create_draft and submit for
-- purchaseRequest in System Access. That user-specific row outranks these
-- role rows (400 vs 200). Workflow review actions (approve/forward/return/
-- reject) are decided by step assignment, not these rows, so Department
-- Heads and other configured reviewers keep their responsibilities.
--
-- Idempotent.

INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
VALUES
  ('employee',   NULL::uuid, 'purchaseRequest', 'create_draft', false),
  ('employee',   NULL::uuid, 'purchaseRequest', 'submit',       false),
  ('hr',         NULL::uuid, 'purchaseRequest', 'create_draft', false),
  ('hr',         NULL::uuid, 'purchaseRequest', 'submit',       false),
  ('supervisor', NULL::uuid, 'purchaseRequest', 'create_draft', false),
  ('supervisor', NULL::uuid, 'purchaseRequest', 'submit',       false)
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();
