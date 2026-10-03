-- Preserve existing admins' DTR access; new admins require explicit grants.
CREATE TABLE IF NOT EXISTS dtr_admin_access (
  admin_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  reports_allowed BOOLEAN NOT NULL DEFAULT false,
  manage_allowed BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO dtr_admin_access (admin_user_id, reports_allowed, manage_allowed)
SELECT id, true, true FROM users WHERE role = 'admin'
ON CONFLICT (admin_user_id) DO NOTHING;
