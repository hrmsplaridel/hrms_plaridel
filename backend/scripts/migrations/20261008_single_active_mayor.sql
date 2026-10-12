-- Preserve past Mayor accounts and approval history, but allow only one active Mayor.
-- If multiple active Mayors already exist, this fails without changing accounts.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE UNIQUE INDEX IF NOT EXISTS users_single_active_mayor_idx
  ON users (role) WHERE role = 'mayor' AND is_active = true;

COMMIT;
