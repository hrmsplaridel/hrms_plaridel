ALTER TABLE dtr_admin_access
  ADD COLUMN IF NOT EXISTS corrections_allowed BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS employees_allowed BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS leave_allowed BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS approvals_allowed BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS locator_allowed BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE dtr_admin_access
  ALTER COLUMN corrections_allowed SET DEFAULT false,
  ALTER COLUMN employees_allowed SET DEFAULT false,
  ALTER COLUMN leave_allowed SET DEFAULT false,
  ALTER COLUMN approvals_allowed SET DEFAULT false,
  ALTER COLUMN locator_allowed SET DEFAULT false;
