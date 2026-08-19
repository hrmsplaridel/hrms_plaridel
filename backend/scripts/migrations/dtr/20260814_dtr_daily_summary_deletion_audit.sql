-- Preserve raw biometric evidence when an administrator deletes a processed DTR entry.
-- A deletion record also prevents biometric processing from recreating that employee/date.

CREATE TABLE IF NOT EXISTS dtr_daily_summary_deletions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  deleted_dtr_summary_id UUID NOT NULL,
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  attendance_date DATE NOT NULL,
  source TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
  deleted_by UUID REFERENCES users(id) ON DELETE SET NULL,
  record_snapshot JSONB NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  restored_by UUID REFERENCES users(id) ON DELETE SET NULL,
  restoration_reason TEXT CHECK (
    restoration_reason IS NULL OR btrim(restoration_reason) <> ''
  ),
  restored_at TIMESTAMPTZ
);

ALTER TABLE dtr_daily_summary_deletions
  ADD COLUMN IF NOT EXISTS restored_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS restoration_reason TEXT,
  ADD COLUMN IF NOT EXISTS restored_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_dtr_summary_deletions_employee_date
  ON dtr_daily_summary_deletions(employee_id, attendance_date);

CREATE INDEX IF NOT EXISTS idx_dtr_summary_deletions_deleted_at
  ON dtr_daily_summary_deletions(deleted_at DESC);

CREATE INDEX IF NOT EXISTS idx_dtr_summary_deletions_active
  ON dtr_daily_summary_deletions(employee_id, attendance_date)
  WHERE restored_at IS NULL;

COMMENT ON TABLE dtr_daily_summary_deletions IS
  'Immutable audit snapshots of processed DTR entries deleted by an administrator. Matching raw biometric logs remain preserved.';
