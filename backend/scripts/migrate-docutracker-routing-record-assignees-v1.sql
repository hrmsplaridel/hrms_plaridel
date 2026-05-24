-- DocuTracker: allow multiple assignees per routing step (v1)
--
-- Adds a join table so a workflow step can have multiple assigned reviewers/signatories.
-- Backfills existing rows from docutracker_routing_records.assignee_id.

BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_routing_record_assignees (
  routing_record_id UUID NOT NULL REFERENCES docutracker_routing_records(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (routing_record_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_record_assignees_user
  ON docutracker_routing_record_assignees(user_id);

-- Backfill from legacy single-assignee column.
INSERT INTO docutracker_routing_record_assignees (routing_record_id, user_id)
SELECT rr.id, rr.assignee_id
FROM docutracker_routing_records rr
WHERE rr.assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

COMMIT;

