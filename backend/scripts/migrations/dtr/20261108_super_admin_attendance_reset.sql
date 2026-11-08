-- Retain exact punch exclusions when attendance is reset. This prevents the
-- physical clock or a later file import from replaying the removed evidence.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS attendance_reset_punches (
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  logged_at TIMESTAMPTZ NOT NULL,
  reset_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, logged_at)
);

COMMIT;
