-- Preserve historical assignment schedules and freeze leave review routing.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260806_leave_review_routing_snapshot.sql

ALTER TABLE leave_requests
  ADD COLUMN IF NOT EXISTS review_department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_department_head_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_leave_requests_review_department
  ON leave_requests(review_department_id);

CREATE INDEX IF NOT EXISTS idx_leave_requests_assigned_department_head
  ON leave_requests(assigned_department_head_id, status);

-- Backfill the department effective on the latest submission/resubmission date.
UPDATE leave_requests lr
SET review_department_id = (
  SELECT a.department_id
  FROM assignments a
  WHERE a.employee_id = COALESCE(lr.user_id, lr.employee_id)
    AND a.department_id IS NOT NULL
    AND a.effective_from <= COALESCE(
      (
        SELECT h.acted_at::date
        FROM leave_request_history h
        WHERE h.leave_request_id = lr.id
          AND h.action IN ('submitted', 'resubmitted')
        ORDER BY h.acted_at DESC
        LIMIT 1
      ),
      lr.created_at::date
    )
    AND (a.effective_to IS NULL OR a.effective_to >= COALESCE(
      (
        SELECT h.acted_at::date
        FROM leave_request_history h
        WHERE h.leave_request_id = lr.id
          AND h.action IN ('submitted', 'resubmitted')
        ORDER BY h.acted_at DESC
        LIMIT 1
      ),
      lr.created_at::date
    ))
  ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
  LIMIT 1
)
WHERE lr.review_department_id IS NULL
  AND (
    lr.status <> 'draft'
    OR EXISTS (
      SELECT 1
      FROM leave_request_history h
      WHERE h.leave_request_id = lr.id
        AND h.action IN ('submitted', 'resubmitted')
    )
  );

-- Prefer the latest submission snapshot. For older resubmissions that did not
-- persist it, use the actual reviewer history, then the head effective on the
-- resubmission date in the snapshotted department.
UPDATE leave_requests lr
SET assigned_department_head_id = COALESCE(
  (
    SELECT CASE
      WHEN COALESCE(h.metadata_json->>'department_head', '')
           ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      THEN (h.metadata_json->>'department_head')::uuid
      ELSE NULL
    END
    FROM leave_request_history h
    WHERE h.leave_request_id = lr.id
      AND h.action IN ('submitted', 'resubmitted')
    ORDER BY h.acted_at DESC
    LIMIT 1
  ),
  (
    SELECT h.acted_by
    FROM leave_request_history h
    WHERE h.leave_request_id = lr.id
      AND h.action IN (
        'department_head_approved',
        'department_head_rejected',
        'department_head_returned'
      )
      AND h.acted_by IS NOT NULL
    ORDER BY h.acted_at DESC
    LIMIT 1
  ),
  (
    SELECT head_a.employee_id
    FROM assignments head_a
    JOIN positions p ON p.id = head_a.position_id
    WHERE lr.status = 'pending_department_head'
      AND head_a.department_id = lr.review_department_id
      AND (
        LOWER(p.name) = 'department head'
        OR p.name ILIKE '%department head%'
      )
      AND (head_a.effective_from IS NULL OR head_a.effective_from <= COALESCE(
        (
          SELECT h.acted_at::date
          FROM leave_request_history h
          WHERE h.leave_request_id = lr.id
            AND h.action IN ('submitted', 'resubmitted')
          ORDER BY h.acted_at DESC
          LIMIT 1
        ),
        lr.created_at::date
      ))
      AND (head_a.effective_to IS NULL OR head_a.effective_to >= COALESCE(
        (
          SELECT h.acted_at::date
          FROM leave_request_history h
          WHERE h.leave_request_id = lr.id
            AND h.action IN ('submitted', 'resubmitted')
          ORDER BY h.acted_at DESC
          LIMIT 1
        ),
        lr.created_at::date
      ))
    ORDER BY head_a.effective_from DESC NULLS LAST,
             head_a.created_at DESC NULLS LAST,
             head_a.id DESC
    LIMIT 1
  )
)
WHERE lr.assigned_department_head_id IS NULL
  AND (
    lr.status <> 'draft'
    OR EXISTS (
      SELECT 1
      FROM leave_request_history h
      WHERE h.leave_request_id = lr.id
        AND h.action IN ('submitted', 'resubmitted')
    )
  );
