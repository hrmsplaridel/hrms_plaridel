CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS locator_attachment_access_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  locator_slip_id UUID REFERENCES locator_slips(id) ON DELETE SET NULL,
  attachment_name TEXT,
  accessed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_role TEXT,
  access_reason TEXT NOT NULL,
  access_outcome TEXT NOT NULL
    CHECK (access_outcome IN ('allowed', 'denied', 'missing_attachment', 'missing_file')),
  ip_address TEXT,
  user_agent TEXT,
  accessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_locator_attachment_access_request_time
  ON locator_attachment_access_logs(locator_slip_id, accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_locator_attachment_access_actor_time
  ON locator_attachment_access_logs(accessed_by, accessed_at DESC);
