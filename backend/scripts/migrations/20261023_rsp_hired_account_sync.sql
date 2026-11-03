-- Explicit upgrade for the account-link synchronization introduced by the RSP merge.
-- Mirrors ensureRspApplicationsTables; preserves later manual "Not yet" choices.
BEGIN;

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS hr_account_setup_linked_sync BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.recruitment_applications
SET hr_account_setup_done = TRUE,
    hr_account_setup_linked_sync = TRUE,
    updated_at = now()
WHERE hr_account_setup_linked_sync IS NOT TRUE
  AND (hired_user_id IS NOT NULL OR status = 'registered');

COMMIT;
