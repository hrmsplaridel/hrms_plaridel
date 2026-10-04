ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_version INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS password_reset_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  handled_by UUID REFERENCES users(id) ON DELETE SET NULL,
  closed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS password_reset_requests_open_user
  ON password_reset_requests(user_id) WHERE status IN ('pending', 'sent');
CREATE INDEX IF NOT EXISTS password_reset_requests_created ON password_reset_requests(created_at DESC);
ALTER TABLE auth_password_reset_otps ADD COLUMN IF NOT EXISTS assistance_request_id UUID
  REFERENCES password_reset_requests(id) ON DELETE SET NULL;
