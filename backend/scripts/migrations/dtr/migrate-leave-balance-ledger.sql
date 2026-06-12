-- Idempotent: leave_balance_ledger (append-only balance audit).
-- Also created at runtime by backend/src/services/leaveBalanceLedger.js (initLeaveBalanceLedger).
-- Run manually if needed: psql $DATABASE_URL -f backend/scripts/migrations/dtr/migrate-leave-balance-ledger.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS leave_balance_ledger (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type TEXT NOT NULL,
  action TEXT NOT NULL,
  affected_bucket TEXT NOT NULL,
  days_changed NUMERIC NOT NULL DEFAULT 0,
  old_value NUMERIC,
  new_value NUMERIC,
  related_leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_kind TEXT NOT NULL DEFAULT 'user',
  remarks TEXT,
  metadata_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_user_created
  ON leave_balance_ledger(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_action
  ON leave_balance_ledger(action);
CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_leave_request
  ON leave_balance_ledger(related_leave_request_id)
  WHERE related_leave_request_id IS NOT NULL;
