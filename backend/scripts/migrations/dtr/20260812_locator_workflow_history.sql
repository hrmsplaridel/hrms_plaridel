BEGIN;

CREATE TABLE IF NOT EXISTS locator_slip_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  locator_slip_id UUID NOT NULL REFERENCES locator_slips(id) ON DELETE RESTRICT,
  action TEXT NOT NULL CHECK (char_length(btrim(action)) > 0),
  from_status TEXT,
  to_status TEXT,
  actor_id UUID,
  actor_name_snapshot TEXT,
  actor_role TEXT,
  remarks TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_locator_slip_history_request_time
  ON locator_slip_history(locator_slip_id, created_at, id);

INSERT INTO locator_slip_history (
  locator_slip_id, action, from_status, to_status, actor_id,
  actor_name_snapshot, actor_role, remarks, metadata, created_at
)
SELECT
  slip.id,
  CASE
    WHEN slip.is_retroactive_correction THEN 'retroactive_correction_recorded'
    ELSE 'submitted'
  END,
  NULL,
  CASE
    WHEN slip.is_retroactive_correction THEN 'approved'
    WHEN slip.assigned_department_head_id IS NULL THEN 'pending_hr'
    ELSE 'pending_department_head'
  END,
  CASE
    WHEN slip.is_retroactive_correction THEN slip.retroactive_corrected_by
    ELSE slip.employee_id
  END,
  actor.full_name,
  CASE
    WHEN slip.is_retroactive_correction THEN 'hr'
    ELSE 'employee'
  END,
  CASE
    WHEN slip.is_retroactive_correction THEN slip.retroactive_correction_reason
    ELSE NULL
  END,
  '{"legacy_backfill":true}'::jsonb,
  COALESCE(slip.retroactive_corrected_at, slip.created_at)
FROM locator_slips slip
LEFT JOIN users actor ON actor.id = CASE
  WHEN slip.is_retroactive_correction THEN slip.retroactive_corrected_by
  ELSE slip.employee_id
END
WHERE NOT EXISTS (
  SELECT 1
  FROM locator_slip_history history
  WHERE history.locator_slip_id = slip.id
    AND history.action IN ('submitted', 'retroactive_correction_recorded')
);

INSERT INTO locator_slip_history (
  locator_slip_id, action, from_status, to_status, actor_id,
  actor_name_snapshot, actor_role, remarks, metadata, created_at
)
SELECT
  slip.id,
  CASE
    WHEN slip.status = 'rejected_by_department_head' THEN 'department_head_rejected'
    WHEN slip.status = 'returned_for_correction' AND slip.hr_reviewed_at IS NULL
      THEN 'department_head_returned'
    ELSE 'department_head_approved'
  END,
  'pending_department_head',
  CASE
    WHEN slip.status = 'rejected_by_department_head' THEN 'rejected_by_department_head'
    WHEN slip.status = 'returned_for_correction' AND slip.hr_reviewed_at IS NULL
      THEN 'returned_for_correction'
    ELSE 'pending_hr'
  END,
  slip.dept_head_reviewer_id,
  reviewer.full_name,
  'department_head',
  slip.dept_head_remarks,
  '{"legacy_backfill":true}'::jsonb,
  slip.dept_head_reviewed_at
FROM locator_slips slip
LEFT JOIN users reviewer ON reviewer.id = slip.dept_head_reviewer_id
WHERE slip.dept_head_reviewed_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM locator_slip_history history
    WHERE history.locator_slip_id = slip.id
      AND history.actor_role = 'department_head'
      AND history.created_at = slip.dept_head_reviewed_at
  );

INSERT INTO locator_slip_history (
  locator_slip_id, action, from_status, to_status, actor_id,
  actor_name_snapshot, actor_role, remarks, metadata, created_at
)
SELECT
  slip.id,
  CASE
    WHEN slip.status = 'rejected_by_hr' THEN 'hr_rejected'
    WHEN slip.status = 'returned_for_correction' OR slip.status = 'pending_hr'
      THEN 'hr_returned'
    ELSE 'hr_approved'
  END,
  'pending_hr',
  CASE
    WHEN slip.status = 'rejected_by_hr' THEN 'rejected_by_hr'
    WHEN slip.status = 'returned_for_correction' OR slip.status = 'pending_hr'
      THEN 'returned_for_correction'
    ELSE 'approved'
  END,
  slip.hr_reviewer_id,
  reviewer.full_name,
  'hr',
  slip.hr_remarks,
  '{"legacy_backfill":true}'::jsonb,
  slip.hr_reviewed_at
FROM locator_slips slip
LEFT JOIN users reviewer ON reviewer.id = slip.hr_reviewer_id
WHERE slip.hr_reviewed_at IS NOT NULL
  AND slip.is_retroactive_correction = false
  AND NOT EXISTS (
    SELECT 1
    FROM locator_slip_history history
    WHERE history.locator_slip_id = slip.id
      AND history.actor_role = 'hr'
      AND history.created_at = slip.hr_reviewed_at
  );

INSERT INTO locator_slip_history (
  locator_slip_id, action, from_status, to_status, actor_id,
  actor_name_snapshot, actor_role, remarks, metadata, created_at
)
SELECT
  slip.id,
  'approval_revoked',
  'approved',
  'revoked',
  slip.revoked_by,
  revoker.full_name,
  'hr',
  slip.revocation_reason,
  jsonb_build_object(
    'legacy_backfill', true,
    'reconciliation_required', slip.month_end_reconciliation_required
  ),
  slip.revoked_at
FROM locator_slips slip
LEFT JOIN users revoker ON revoker.id = slip.revoked_by
WHERE slip.status = 'revoked'
  AND slip.revoked_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM locator_slip_history history
    WHERE history.locator_slip_id = slip.id
      AND history.action = 'approval_revoked'
  );

INSERT INTO locator_slip_history (
  locator_slip_id, action, from_status, to_status, actor_id,
  actor_name_snapshot, actor_role, metadata, created_at
)
SELECT
  slip.id,
  'cancelled',
  NULL,
  'cancelled',
  slip.employee_id,
  employee.full_name,
  'employee',
  '{"legacy_backfill":true,"from_status_unknown":true}'::jsonb,
  slip.updated_at
FROM locator_slips slip
LEFT JOIN users employee ON employee.id = slip.employee_id
WHERE slip.status = 'cancelled'
  AND NOT EXISTS (
    SELECT 1
    FROM locator_slip_history history
    WHERE history.locator_slip_id = slip.id
      AND history.action = 'cancelled'
  );

CREATE OR REPLACE FUNCTION prevent_locator_slip_history_mutation()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'locator_slip_history is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_locator_slip_history_mutation
  ON locator_slip_history;
CREATE TRIGGER trg_prevent_locator_slip_history_mutation
BEFORE UPDATE OR DELETE ON locator_slip_history
FOR EACH ROW EXECUTE FUNCTION prevent_locator_slip_history_mutation();

COMMIT;
