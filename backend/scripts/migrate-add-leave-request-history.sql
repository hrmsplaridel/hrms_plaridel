-- Add leave request history audit table
-- Run: psql -d hrms_plaridel -f backend/scripts/migrate-add-leave-request-history.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS leave_request_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  leave_request_id UUID NOT NULL REFERENCES leave_requests(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  acted_by UUID REFERENCES users(id) ON DELETE SET NULL,
  acted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  remarks TEXT,
  metadata_json JSONB
);

CREATE INDEX IF NOT EXISTS idx_leave_request_history_leave_request_id
  ON leave_request_history(leave_request_id);

