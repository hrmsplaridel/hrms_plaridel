-- Module access for RSP and L&D (parallel to dtr_admin_access; does not alter DTR).
-- Existing admins keep full access; new admins require explicit grants (defaults false).

CREATE TABLE IF NOT EXISTS rsp_admin_access (
  admin_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  vacancies_allowed BOOLEAN NOT NULL DEFAULT false,
  recruitment_allowed BOOLEAN NOT NULL DEFAULT false,
  exams_allowed BOOLEAN NOT NULL DEFAULT false,
  forms_allowed BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ld_admin_access (
  admin_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  forms_allowed BOOLEAN NOT NULL DEFAULT false,
  daily_reports_allowed BOOLEAN NOT NULL DEFAULT false,
  requirements_allowed BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO rsp_admin_access (
  admin_user_id,
  vacancies_allowed,
  recruitment_allowed,
  exams_allowed,
  forms_allowed
)
SELECT id, true, true, true, true
  FROM users
 WHERE role = 'admin'
ON CONFLICT (admin_user_id) DO NOTHING;

INSERT INTO ld_admin_access (
  admin_user_id,
  forms_allowed,
  daily_reports_allowed,
  requirements_allowed
)
SELECT id, true, true, true
  FROM users
 WHERE role = 'admin'
ON CONFLICT (admin_user_id) DO NOTHING;
