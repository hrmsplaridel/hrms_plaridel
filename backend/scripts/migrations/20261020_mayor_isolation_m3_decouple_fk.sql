-- M3 — Mayor hard isolation (FK decoupling)
-- DO NOT RUN until:
--   1) M1 + M2 applied
--   2) Verified backup exists
--   3) Backend release that uses LEFT JOIN + removes RSP explicit mayor DELETE
--      is ready to deploy in the same window
--
-- Effects:
--   - Drops ON DELETE CASCADE from recruitment_applications
--   - Makes application_id nullable (legacy metadata only)
--   - Replaces UNIQUE(application_id) with partial unique (non-null only)
--   - Drops activity_logs FK to recruitment_applications (column retained)
--
-- ROLLBACK WARNING: Re-adding NOT NULL + CASCADE is unsafe after independent
-- rows with NULL application_id exist. Restore from backup instead.

BEGIN;

-- Drop endorsement → recruitment FK (CASCADE risk).
ALTER TABLE public.mayor_endorsement_requests
  DROP CONSTRAINT IF EXISTS mayor_endorsement_requests_application_id_fkey;

-- Drop hard UNIQUE so multiple NULL application_id values are allowed.
ALTER TABLE public.mayor_endorsement_requests
  DROP CONSTRAINT IF EXISTS mayor_endorsement_requests_application_id_key;

DROP INDEX IF EXISTS public.mayor_endorsement_requests_application_id_key;

-- Allow independent endorsements with no recruitment application.
ALTER TABLE public.mayor_endorsement_requests
  ALTER COLUMN application_id DROP NOT NULL;

-- Preserve one-endorsement-per-legacy-application for non-null links only.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mayor_endorsement_requests_application_id_legacy
  ON public.mayor_endorsement_requests (application_id)
  WHERE application_id IS NOT NULL;

-- Activity log: keep application_id as nullable legacy metadata, remove FK.
ALTER TABLE public.mayor_endorsement_activity_logs
  DROP CONSTRAINT IF EXISTS mayor_endorsement_activity_logs_application_id_fkey;

COMMENT ON COLUMN public.mayor_endorsement_requests.application_id IS
  'Legacy optional link to recruitment_applications. Non-authoritative after hard isolation. New endorsements leave this NULL.';

COMMENT ON COLUMN public.mayor_endorsement_activity_logs.application_id IS
  'Legacy optional recruitment application id. Not required for Mayor endorsement audit.';

COMMIT;
