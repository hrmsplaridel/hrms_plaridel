-- Migration: effective-dated official Department Head designations
-- Run against an existing database before deploying the matching backend.

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS position_department_head_periods (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_id UUID NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_position_department_head_period_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- The old index allowed only one Boolean flag per department. Period overlap
-- now provides the stronger date-aware rule and permits scheduled transitions.
DROP INDEX IF EXISTS uq_positions_department_head_per_department;

INSERT INTO position_department_head_periods (
  position_id, department_id, effective_from, effective_to, is_active
)
SELECT p.id,
       p.department_id,
       COALESCE(p.created_at::date, CURRENT_DATE),
       NULL,
       true
FROM positions p
WHERE p.is_department_head = true
  AND p.department_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM position_department_head_periods period
    WHERE period.position_id = p.id
      AND period.is_active = true
  );

ALTER TABLE position_department_head_periods
  DROP CONSTRAINT IF EXISTS position_department_head_period_no_overlap;
ALTER TABLE position_department_head_periods
  ADD CONSTRAINT position_department_head_period_no_overlap
  EXCLUDE USING gist (
    department_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
  WHERE (is_active = true);

CREATE INDEX IF NOT EXISTS idx_position_department_head_periods_effective
  ON position_department_head_periods
    (position_id, department_id, effective_from, effective_to)
  WHERE is_active = true;

COMMIT;
