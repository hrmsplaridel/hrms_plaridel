-- Store approved leave dates separately from the underlying DTR summary.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260805_leave_dtr_coverage.sql
-- Existing approvals remain on the legacy DTR path because their overwritten
-- pre-approval state cannot be reconstructed safely. New approvals use this table.

CREATE TABLE IF NOT EXISTS dtr_leave_coverage (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  leave_request_id UUID NOT NULL REFERENCES leave_requests(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_dtr_leave_coverage_request_date
    UNIQUE (leave_request_id, attendance_date),
  CONSTRAINT uq_dtr_leave_coverage_employee_date
    UNIQUE (employee_id, attendance_date)
);

CREATE INDEX IF NOT EXISTS idx_dtr_leave_coverage_employee_date
  ON dtr_leave_coverage(employee_id, attendance_date);

CREATE INDEX IF NOT EXISTS idx_dtr_leave_coverage_request
  ON dtr_leave_coverage(leave_request_id);
