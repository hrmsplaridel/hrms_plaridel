-- One document-revision chance for Step 1 initial docs and Step 5 final requirements
-- (same product rule as the HR-issued form: one return for resubmit, then pass/fail only).

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS document_revision_used BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS final_requirements_revision_used BOOLEAN NOT NULL DEFAULT FALSE;
