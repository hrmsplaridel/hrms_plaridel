-- Phase 4 — Mark disposable endorsement rows without deleting them.
-- Additive only. Official dashboards/reports exclude is_test = true by default.
-- DO NOT RUN until approved (or apply via ensureMayorEndorsementTables bootstrap).

BEGIN;

ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS is_test BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.mayor_endorsement_requests.is_test IS
  'When true, excluded from official Mayor monitoring/PDF totals. Retain for debugging.';

-- Known Phase 2.5 disposable validation rows (exact IDs only).
UPDATE public.mayor_endorsement_requests
   SET is_test = true
 WHERE id IN (
   'bf301de0-0461-45a6-93ff-f350791856c4'::uuid,
   'c77aa381-4c9c-494d-8e10-f8e282d4fac4'::uuid,
   '1dcdeb69-f310-4f01-bfed-c06c2f304855'::uuid
 );

CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_is_test
  ON public.mayor_endorsement_requests (is_test)
  WHERE is_test = true;

COMMIT;
