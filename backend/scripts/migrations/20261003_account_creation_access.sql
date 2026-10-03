-- Preserve existing administrators' access; future administrators start denied.
CREATE TABLE IF NOT EXISTS account_creation_access (
  admin_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  allowed BOOLEAN NOT NULL,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO account_creation_access (admin_user_id, allowed)
SELECT id, true FROM users WHERE role = 'admin'
ON CONFLICT (admin_user_id) DO NOTHING;
