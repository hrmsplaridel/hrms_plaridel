-- DocuTracker strict workflow action enforcement (apply once).
-- Preserve legacy behaviour before the server begins treating empty action lists
-- as deny-all: existing enabled assignees receive the historical full set.

BEGIN;

UPDATE docutracker_workflow_step_assignees
SET allowed_actions = ARRAY['approve', 'forward', 'reject', 'return']::TEXT[],
    updated_at = now()
WHERE is_enabled = true
  AND COALESCE(cardinality(allowed_actions), 0) = 0;

COMMIT;
