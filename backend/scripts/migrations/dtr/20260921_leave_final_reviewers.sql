-- Final leave review is a position assignment with separately ranked backups.
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE positions
  ADD COLUMN IF NOT EXISTS is_leave_final_reviewer BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_leave_final_reviewer_position
  ON positions (is_leave_final_reviewer)
  WHERE is_leave_final_reviewer = true AND is_active = true;

CREATE TABLE IF NOT EXISTS leave_final_reviewer_backups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  backup_rank INTEGER NOT NULL CHECK (backup_rank > 0),
  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_leave_final_reviewer_backup_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

ALTER TABLE leave_final_reviewer_backups
  DROP CONSTRAINT IF EXISTS leave_final_reviewer_backup_employee_no_overlap;
ALTER TABLE leave_final_reviewer_backups
  ADD CONSTRAINT leave_final_reviewer_backup_employee_no_overlap
  EXCLUDE USING gist (
    employee_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  ) WHERE (is_active = true);
ALTER TABLE leave_final_reviewer_backups
  DROP CONSTRAINT IF EXISTS leave_final_reviewer_backup_rank_no_overlap;
ALTER TABLE leave_final_reviewer_backups
  ADD CONSTRAINT leave_final_reviewer_backup_rank_no_overlap
  EXCLUDE USING gist (
    backup_rank WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  ) WHERE (is_active = true);
