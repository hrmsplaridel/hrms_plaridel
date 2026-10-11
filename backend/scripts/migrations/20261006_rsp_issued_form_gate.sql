-- HR-issued form between Document Review approval and Assessment.
-- Existing rows keep step2_gate_required = false, so applicants already in
-- Assessment, Deliberation, or Final Hiring are not sent backward.

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS step2_gate_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS required_form_type TEXT,
  ADD COLUMN IF NOT EXISTS required_form_status TEXT,
  ADD COLUMN IF NOT EXISTS required_form_entry_id UUID,
  ADD COLUMN IF NOT EXISTS required_form_assigned_by UUID,
  ADD COLUMN IF NOT EXISTS required_form_assigned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS required_form_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS required_form_reviewed_by UUID,
  ADD COLUMN IF NOT EXISTS required_form_reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS required_form_review_comment TEXT,
  ADD COLUMN IF NOT EXISTS required_form_review_log JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.bi_form_entries
  ADD COLUMN IF NOT EXISTS application_id UUID;

ALTER TABLE public.ojt_work_immersion_evaluation_entries
  ADD COLUMN IF NOT EXISTS application_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_bi_form_entries_application
  ON public.bi_form_entries (application_id)
  WHERE application_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ojt_entries_application
  ON public.ojt_work_immersion_evaluation_entries (application_id)
  WHERE application_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_required_form_type_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_required_form_type_check
      CHECK (required_form_type IS NULL OR required_form_type IN ('bi', 'ojt'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_required_form_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      ADD CONSTRAINT recruitment_applications_required_form_status_check
      CHECK (
        required_form_status IS NULL OR required_form_status IN (
          'waiting_for_hr_form',
          'assigned',
          'in_progress',
          'submitted_for_review',
          'needs_revision',
          'resubmitted_for_review',
          'approved'
        )
      );
  END IF;
END $$;
