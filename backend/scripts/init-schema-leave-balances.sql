-- HRMS Plaridel - Leave Balances
-- Run AFTER init-schema.sql (requires: users)
-- Run: psql -d hrms_plaridel -f scripts/init-schema-leave-balances.sql

-- =========================
-- LEAVE BALANCES
-- =========================
CREATE TABLE IF NOT EXISTS leave_balances (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type TEXT NOT NULL,
  earned_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (earned_days >= 0),
  used_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (used_days >= 0),
  pending_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (pending_days >= 0),
  adjusted_days NUMERIC(8,2) NOT NULL DEFAULT 0,
  as_of_date DATE,
  last_accrual_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, leave_type)
);

CREATE INDEX IF NOT EXISTS idx_leave_balances_user_id ON leave_balances(user_id);
