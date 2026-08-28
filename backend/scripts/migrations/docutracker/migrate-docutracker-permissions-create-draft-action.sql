-- Allow DocuTracker permission rows to use the canonical create_draft action.
-- Older databases may still have docutracker_permissions_action_check, which
-- allowed create but rejected create_draft.

ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check;
ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check_v1;
ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_action_check_prod_v1;

ALTER TABLE docutracker_permissions
  ADD CONSTRAINT docutracker_permissions_action_check_prod_v1
  CHECK (action IN (
    'view',
    'create',
    'create_draft',
    'submit',
    'download',
    'edit',
    'delete',
    'forward',
    'approve',
    'reject',
    'return'
  ));
