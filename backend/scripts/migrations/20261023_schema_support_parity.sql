-- Bring older support objects into line with the complete fresh initializer.
-- No data backfill: invalid legacy data causes rollback rather than modification.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.user_push_tokens'::regclass
      AND tgname = 'trg_user_push_tokens_updated_at'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_user_push_tokens_updated_at
    BEFORE UPDATE ON public.user_push_tokens
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

ALTER TABLE public.leave_requests ALTER COLUMN user_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.dtr_daily_summary_deletions'::regclass
      AND conname = 'dtr_daily_summary_deletions_restoration_reason_check'
  ) THEN
    ALTER TABLE public.dtr_daily_summary_deletions
      ADD CONSTRAINT dtr_daily_summary_deletions_restoration_reason_check
      CHECK (restoration_reason IS NULL OR btrim(restoration_reason) <> '') NOT VALID;
  END IF;
END $$;

ALTER TABLE public.dtr_daily_summary_deletions
  VALIDATE CONSTRAINT dtr_daily_summary_deletions_restoration_reason_check;

COMMIT;
