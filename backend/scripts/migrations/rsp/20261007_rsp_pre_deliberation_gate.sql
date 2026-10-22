-- Pre-deliberation requirements before the existing deliberation schedule.
-- Existing rows keep step4_gate_required = false, so applicants already
-- scheduled, in deliberation, or in Final Hiring are not sent backward.

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS step4_gate_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS wes_status TEXT,
  ADD COLUMN IF NOT EXISTS wes_entry_id UUID,
  ADD COLUMN IF NOT EXISTS wes_assigned_by UUID,
  ADD COLUMN IF NOT EXISTS wes_assigned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS wes_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS wes_reviewed_by UUID,
  ADD COLUMN IF NOT EXISTS wes_reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS wes_review_comment TEXT,
  ADD COLUMN IF NOT EXISTS applicants_profile_entry_id UUID,
  ADD COLUMN IF NOT EXISTS applicants_profile_status TEXT,
  ADD COLUMN IF NOT EXISTS applicants_profile_completed_by UUID,
  ADD COLUMN IF NOT EXISTS applicants_profile_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS selection_lineup_entry_id UUID,
  ADD COLUMN IF NOT EXISTS selection_lineup_status TEXT,
  ADD COLUMN IF NOT EXISTS selection_lineup_completed_by UUID,
  ADD COLUMN IF NOT EXISTS selection_lineup_completed_at TIMESTAMPTZ;

ALTER TABLE public.work_experience_sheet_entries
  ADD COLUMN IF NOT EXISTS application_id UUID;

ALTER TABLE public.applicants_profile_entries
  ADD COLUMN IF NOT EXISTS application_id UUID;

ALTER TABLE public.selection_lineup_entries
  ADD COLUMN IF NOT EXISTS application_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_experience_sheet_application
  ON public.work_experience_sheet_entries (application_id)
  WHERE application_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_applicants_profile_application
  ON public.applicants_profile_entries (application_id)
  WHERE application_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_selection_lineup_application
  ON public.selection_lineup_entries (application_id)
  WHERE application_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_wes_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_wes_status_check
      CHECK (
        wes_status IS NULL OR wes_status IN (
          'waiting_for_work_experience_sheet',
          'assigned',
          'in_progress',
          'submitted_for_review',
          'needs_revision',
          'resubmitted_for_review',
          'approved'
        )
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_profile_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_profile_status_check
      CHECK (
        applicants_profile_status IS NULL
        OR applicants_profile_status IN ('waiting', 'in_progress', 'completed')
      );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_lineup_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_lineup_status_check
      CHECK (
        selection_lineup_status IS NULL
        OR selection_lineup_status IN ('waiting', 'in_progress', 'completed')
      );
  END IF;
END $$;
