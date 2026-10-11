-- Final Hiring preparation before the existing Final Requirements flow.
-- Existing rows keep step5_gate_required = false, so applicants already
-- uploading requirements, in orientation, or hired are not sent backward.

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS step5_gate_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS tat_entry_id UUID,
  ADD COLUMN IF NOT EXISTS tat_status TEXT,
  ADD COLUMN IF NOT EXISTS tat_completed_by UUID,
  ADD COLUMN IF NOT EXISTS tat_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS csc_approval_status TEXT,
  ADD COLUMN IF NOT EXISTS csc_approved_by UUID,
  ADD COLUMN IF NOT EXISTS csc_approved_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_tat_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_tat_status_check
      CHECK (
        tat_status IS NULL
        OR tat_status IN ('waiting', 'in_progress', 'completed')
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_csc_approval_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_csc_approval_status_check
      CHECK (
        csc_approval_status IS NULL
        OR csc_approval_status IN ('waiting', 'approved')
      );
  END IF;
END $$;
