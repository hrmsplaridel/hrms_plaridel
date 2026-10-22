-- M1 — Mayor hard isolation (additive prep)
-- DO NOT RUN until explicitly approved. Non-destructive: ADD COLUMN only.
-- Target DB: hrms_plaridel
-- Depends on: existing mayor_endorsement_requests / activity_logs

BEGIN;

ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS reference_number TEXT,
  ADD COLUMN IF NOT EXISTS applicant_full_name TEXT,
  ADD COLUMN IF NOT EXISTS endorsed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS meeting_request_status TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS meeting_proposed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS meeting_purpose TEXT,
  ADD COLUMN IF NOT EXISTS meeting_decision TEXT,
  ADD COLUMN IF NOT EXISTS meeting_decided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS meeting_decided_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS meeting_decision_remarks TEXT,
  ADD COLUMN IF NOT EXISTS meeting_reschedule_proposed_at TIMESTAMPTZ;

-- Meeting request lifecycle (independent from endorsement status).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'mayor_endorsement_requests'
      AND con.conname = 'mayor_endorsement_requests_meeting_request_status_check'
  ) THEN
    ALTER TABLE public.mayor_endorsement_requests
      ADD CONSTRAINT mayor_endorsement_requests_meeting_request_status_check
      CHECK (
        meeting_request_status = ANY (
          ARRAY[
            'none'::text,
            'submitted'::text,
            'approved'::text,
            'reschedule_requested'::text,
            'declined'::text
          ]
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'mayor_endorsement_requests'
      AND con.conname = 'mayor_endorsement_requests_meeting_decision_check'
  ) THEN
    ALTER TABLE public.mayor_endorsement_requests
      ADD CONSTRAINT mayor_endorsement_requests_meeting_decision_check
      CHECK (
        meeting_decision IS NULL
        OR meeting_decision = ANY (
          ARRAY['approved'::text, 'declined'::text, 'reschedule_requested'::text]
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_office
  ON public.mayor_endorsement_requests (requested_office_id, destination_office_id);

CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_meeting_request_status
  ON public.mayor_endorsement_requests (meeting_request_status);

CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_endorsed_at
  ON public.mayor_endorsement_requests (endorsed_at DESC NULLS LAST);

COMMIT;
