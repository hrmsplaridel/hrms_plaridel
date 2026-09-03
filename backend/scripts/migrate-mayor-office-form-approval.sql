-- Two-step mayor endorsement:
-- 1) Municipal Mayor approves → status = mayor_approved
-- 2) Mayor's Office staff approves endorsement form → status = endorsed
--
-- Run:
--   psql -d hrms_plaridel -f backend/scripts/migrate-mayor-office-form-approval.sql

BEGIN;

DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'mayor_endorsement_requests'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%status IN (%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.mayor_endorsement_requests DROP CONSTRAINT IF EXISTS %I',
      c.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.mayor_endorsement_requests
  DROP CONSTRAINT IF EXISTS mayor_endorsement_requests_status_check;

ALTER TABLE public.mayor_endorsement_requests
  ADD CONSTRAINT mayor_endorsement_requests_status_check
  CHECK (status IN ('pending', 'mayor_approved', 'endorsed', 'rejected'));

ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS office_form_approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS office_form_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

COMMIT;
