-- DocuTracker: allow workflow steps to remain unassigned during configuration.
--
-- Existing assigned steps still require at least one enabled assignee and
-- exactly one enabled primary assignee. Workflow execution remains responsible
-- for rejecting a transition into a step that has no valid assignee.

BEGIN;

CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  sid uuid;
  assignee_count int;
  enabled_count int;
  enabled_primary_count int;
BEGIN
  sid := COALESCE(NEW.step_id, OLD.step_id);
  IF sid IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM docutracker_workflow_steps WHERE id = sid) THEN
    RETURN NULL;
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE a.is_enabled = true),
    COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true)
  INTO assignee_count, enabled_count, enabled_primary_count
  FROM docutracker_workflow_step_assignees a
  WHERE a.step_id = sid;

  IF assignee_count = 0 THEN
    RETURN NULL;
  END IF;

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

COMMIT;
