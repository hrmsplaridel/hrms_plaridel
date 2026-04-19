-- DocuTracker: stronger validation for selected-person workflow assignees (constraints v1)
--
-- Enforces at COMMIT time (deferrable) that:
-- - each workflow step has at least one ENABLED assignee row
-- - exactly one ENABLED primary assignee exists per step
--
-- This complements existing UNIQUE constraints and API-level validation.

BEGIN;

-- Create a constraint trigger that checks per-step invariants.
CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  sid uuid;
  enabled_count int;
  enabled_primary_count int;
BEGIN
  sid := COALESCE(NEW.step_id, OLD.step_id);
  IF sid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE a.is_enabled = true) AS enabled_count,
    COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true) AS enabled_primary_count
  INTO enabled_count, enabled_primary_count
  FROM docutracker_workflow_step_assignees a
  WHERE a.step_id = sid;

  IF enabled_count < 1 THEN
    RAISE EXCEPTION 'Workflow step % must have at least one enabled assignee', sid
      USING ERRCODE = '23514';
  END IF;

  IF enabled_primary_count <> 1 THEN
    RAISE EXCEPTION 'Workflow step % must have exactly one enabled primary assignee', sid
      USING ERRCODE = '23514';
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_docutracker_step_assignees_invariants ON docutracker_workflow_step_assignees;

CREATE CONSTRAINT TRIGGER trg_docutracker_step_assignees_invariants
AFTER INSERT OR UPDATE OR DELETE
ON docutracker_workflow_step_assignees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION docutracker_enforce_step_assignees_invariants();

COMMIT;

