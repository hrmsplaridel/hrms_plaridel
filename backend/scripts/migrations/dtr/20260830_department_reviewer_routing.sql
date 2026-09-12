-- Migration: authoritative department reviewer routing
-- Run against an existing database before deploying the matching backend.

BEGIN;

ALTER TABLE positions
  ADD COLUMN IF NOT EXISTS is_department_head BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE positions
  DROP CONSTRAINT IF EXISTS chk_position_department_head_department;
ALTER TABLE positions
  ADD CONSTRAINT chk_position_department_head_department
  CHECK (is_department_head = false OR department_id IS NOT NULL);

-- Backfill only the old exact convention when a department has one clear match.
UPDATE positions p
SET is_department_head = true,
    updated_at = now()
WHERE lower(btrim(p.name)) = 'department head'
  AND p.department_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM positions other
    WHERE other.department_id = p.department_id
      AND other.id <> p.id
      AND lower(btrim(other.name)) = 'department head'
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_positions_department_head_per_department
  ON positions (department_id)
  WHERE is_department_head = true AND department_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS department_reviewer_backups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  department_id UUID NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  backup_rank INT NOT NULL CHECK (backup_rank > 0),
  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  remarks TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_department_reviewer_backup_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

ALTER TABLE department_reviewer_backups
  DROP CONSTRAINT IF EXISTS department_reviewer_backup_rank_no_overlap;
ALTER TABLE department_reviewer_backups
  ADD CONSTRAINT department_reviewer_backup_rank_no_overlap
  EXCLUDE USING gist (
    department_id WITH =,
    backup_rank WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
  WHERE (is_active = true);

ALTER TABLE department_reviewer_backups
  DROP CONSTRAINT IF EXISTS department_reviewer_employee_no_overlap;
ALTER TABLE department_reviewer_backups
  ADD CONSTRAINT department_reviewer_employee_no_overlap
  EXCLUDE USING gist (
    department_id WITH =,
    employee_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
  WHERE (is_active = true);

CREATE INDEX IF NOT EXISTS idx_department_reviewer_backups_effective
  ON department_reviewer_backups
    (department_id, effective_from, effective_to, backup_rank)
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS leave_request_department_reviewers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  leave_request_id UUID NOT NULL REFERENCES leave_requests(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewer_name_snapshot TEXT NOT NULL,
  reviewer_role TEXT NOT NULL CHECK (reviewer_role IN ('primary', 'backup')),
  backup_rank INT CHECK (backup_rank IS NULL OR backup_rank > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_leave_reviewer_rank CHECK (
    (reviewer_role = 'primary' AND backup_rank IS NULL)
    OR (reviewer_role = 'backup' AND backup_rank IS NOT NULL)
  ),
  UNIQUE (leave_request_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_leave_request_department_reviewers_user
  ON leave_request_department_reviewers(reviewer_id, leave_request_id);

CREATE TABLE IF NOT EXISTS locator_slip_department_reviewers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  locator_slip_id UUID NOT NULL REFERENCES locator_slips(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewer_name_snapshot TEXT NOT NULL,
  reviewer_role TEXT NOT NULL CHECK (reviewer_role IN ('primary', 'backup')),
  backup_rank INT CHECK (backup_rank IS NULL OR backup_rank > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_locator_reviewer_rank CHECK (
    (reviewer_role = 'primary' AND backup_rank IS NULL)
    OR (reviewer_role = 'backup' AND backup_rank IS NOT NULL)
  ),
  UNIQUE (locator_slip_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_locator_slip_department_reviewers_user
  ON locator_slip_department_reviewers(reviewer_id, locator_slip_id);

ALTER TABLE docutracker_workflow_steps
  ADD COLUMN IF NOT EXISTS assignee_source TEXT NOT NULL DEFAULT 'specific_users';

ALTER TABLE docutracker_workflow_steps
  DROP CONSTRAINT IF EXISTS docutracker_workflow_steps_assignee_source_check;
ALTER TABLE docutracker_workflow_steps
  ADD CONSTRAINT docutracker_workflow_steps_assignee_source_check
  CHECK (assignee_source IN ('specific_users', 'department_reviewers'));

COMMIT;
