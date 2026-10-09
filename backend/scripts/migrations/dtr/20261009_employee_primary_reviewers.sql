BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE EXTENSION IF NOT EXISTS btree_gist;

DO $migration$
DECLARE initialize BOOLEAN := to_regclass('public.primary_reviewer_designations') IS NULL;
BEGIN
CREATE TABLE IF NOT EXISTS primary_reviewer_designations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  scope_key TEXT NOT NULL,
  department_id UUID REFERENCES departments(id) ON DELETE RESTRICT,
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  position_id UUID REFERENCES positions(id) ON DELETE SET NULL,
  position_title_snapshot TEXT,
  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CHECK ((scope_key = 'final_hr' AND department_id IS NULL)
    OR (department_id IS NOT NULL AND scope_key = 'department:' || department_id::text)),
  CONSTRAINT primary_reviewer_no_overlap EXCLUDE USING gist (
    scope_key WITH =, daterange(effective_from, effective_to, '[]') WITH &&
  ) WHERE (is_active = true)
);

IF initialize THEN
-- Split at every assignment/designation boundary. This freezes exactly the
-- employee the previous resolver chose on each date, including future periods.
WITH candidates AS (
  SELECT 'department:' || h.department_id::text AS scope_key, h.department_id,
         a.employee_id, a.position_id, p.name AS title,
         GREATEST(h.effective_from, a.effective_from) AS starts,
         LEAST(h.effective_to, a.effective_to) AS ends,
         a.effective_from AS assignment_start, a.created_at, a.id AS assignment_id
  FROM position_department_head_periods h
  JOIN assignments a ON a.position_id = h.position_id AND a.department_id = h.department_id
  JOIN positions p ON p.id = a.position_id AND p.department_id = a.department_id
  JOIN users u ON u.id = a.employee_id
  WHERE h.is_active = true AND a.is_active = true AND p.is_active = true
    AND u.is_active = true
    AND GREATEST(h.effective_from, a.effective_from) <= COALESCE(LEAST(h.effective_to, a.effective_to), 'infinity'::date)
  UNION ALL
  SELECT 'final_hr', NULL::uuid, a.employee_id, a.position_id, p.name,
         a.effective_from, a.effective_to, a.effective_from, a.created_at, a.id
  FROM positions p JOIN assignments a ON a.position_id = p.id JOIN users u ON u.id = a.employee_id
  WHERE p.is_leave_final_reviewer = true AND p.is_active = true AND a.is_active = true
    AND u.is_active = true AND u.role IN ('admin', 'hr')
), boundaries AS (
  SELECT scope_key, starts AS day FROM candidates
  UNION SELECT scope_key, ends + 1 FROM candidates WHERE ends IS NOT NULL
), intervals AS (
  SELECT scope_key, day, LEAD(day) OVER (PARTITION BY scope_key ORDER BY day) - 1 AS ends
  FROM boundaries
)
INSERT INTO primary_reviewer_designations (
  scope_key, department_id, employee_id, position_id, position_title_snapshot, effective_from, effective_to
)
SELECT i.scope_key, c.department_id, c.employee_id, c.position_id, c.title, i.day, i.ends
FROM intervals i JOIN LATERAL (
  SELECT * FROM candidates c WHERE c.scope_key = i.scope_key AND c.starts <= i.day
    AND (c.ends IS NULL OR c.ends >= i.day)
  ORDER BY assignment_start DESC, created_at DESC, assignment_id DESC LIMIT 1
) c ON true;

-- Keep legacy records as history; positions no longer confer reviewer authority.
UPDATE position_department_head_periods SET is_active = false, updated_at = now() WHERE is_active = true;
UPDATE positions SET is_department_head = false, is_leave_final_reviewer = false
  WHERE is_department_head = true OR is_leave_final_reviewer = true;
END IF;
END;
$migration$;

COMMIT;
