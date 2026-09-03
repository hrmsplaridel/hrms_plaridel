-- Mayor Module migration
-- Run:
--   psql -d hrms_plaridel -f backend/scripts/migrate-add-mayor-module.sql

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('admin', 'hr', 'employee', 'supervisor', 'mayor'));

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
      AND rel.relname = 'recruitment_applications'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%status IN (%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.recruitment_applications DROP CONSTRAINT IF EXISTS %I',
      c.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.recruitment_applications
  DROP CONSTRAINT IF EXISTS recruitment_applications_status_check;

ALTER TABLE public.recruitment_applications
  ADD CONSTRAINT recruitment_applications_status_check
  CHECK (
    status IN (
      'submitted',
      'document_approved',
      'document_declined',
      'exam_taken',
      'passed',
      'failed',
      'registered',
      'endorsed',
      'rejected'
    )
  );

CREATE TABLE IF NOT EXISTS public.mayor_endorsement_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id UUID NOT NULL REFERENCES public.recruitment_applications(id) ON DELETE CASCADE,
  requested_office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  requested_office_name TEXT,
  destination_office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  destination_office_name TEXT,
  priority TEXT NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  intake_form JSONB NOT NULL DEFAULT '{}'::JSONB,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'mayor_approved', 'endorsed', 'rejected')),
  staff_notes TEXT,
  mayor_remarks TEXT,
  rejection_reason TEXT,
  endorsement_letter TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  office_form_approved_at TIMESTAMPTZ,
  office_form_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  rejected_at TIMESTAMPTZ,
  rejected_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (application_id)
);

ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS intake_form JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE TABLE IF NOT EXISTS public.mayor_endorsement_activity_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES public.mayor_endorsement_requests(id) ON DELETE CASCADE,
  application_id UUID REFERENCES public.recruitment_applications(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  remarks TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_status
  ON public.mayor_endorsement_requests(status);
CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_submitted
  ON public.mayor_endorsement_requests(submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_priority
  ON public.mayor_endorsement_requests(priority);
CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_activity_request_created
  ON public.mayor_endorsement_activity_logs(request_id, created_at DESC);

INSERT INTO users (email, password_hash, role, full_name, is_active)
VALUES (
  'mayorsoffice@test.com',
  '$2b$10$uhPv2oXZLwC9WJ7hXjg3NOLTnYrjyWextH30e9CoR/z3JovGmHeyy',
  'mayor',
  'Mayor''s Office',
  true
)
ON CONFLICT (email) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role,
    full_name = EXCLUDED.full_name,
    is_active = true,
    updated_at = now();

COMMIT;
