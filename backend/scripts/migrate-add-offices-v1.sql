-- DocuTracker / HR: offices directory + optional user link for office-based routing.
-- Safe to run once on existing databases. Creates table, links users.office_id, trigger.

CREATE SEQUENCE IF NOT EXISTS offices_office_number_seq;

CREATE TABLE IF NOT EXISTS offices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  office_number INT UNIQUE DEFAULT nextval('offices_office_number_seq'),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS office_id UUID REFERENCES offices(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_office_id ON users(office_id) WHERE office_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_offices_updated_at ON offices;
CREATE TRIGGER trg_offices_updated_at
BEFORE UPDATE ON offices
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();
