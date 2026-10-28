-- Preserve signed paper approval separately from digital approval history.
-- Existing locator rows remain unchanged and continue their configured routes.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE public.locator_slips ADD COLUMN IF NOT EXISTS paper_approval_record JSONB;
COMMIT;
