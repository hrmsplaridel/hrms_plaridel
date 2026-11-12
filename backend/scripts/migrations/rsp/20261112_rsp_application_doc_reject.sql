-- Per-document reject/resubmit for Step 1 application PDFs
-- (same pattern as final-requirement reject reasons).

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS doc_application_letter_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_resume_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_tor_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_reject_reason TEXT;
