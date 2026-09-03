-- Human-readable randomized applicant ID for search/verification.
ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS applicant_number TEXT;

-- Existing rows are backfilled by ensureRspApplicationsTables() on API start.
CREATE UNIQUE INDEX IF NOT EXISTS uq_recruitment_applications_applicant_number
  ON public.recruitment_applications (applicant_number)
  WHERE applicant_number IS NOT NULL AND btrim(applicant_number) <> '';

CREATE INDEX IF NOT EXISTS idx_recruitment_applications_applicant_number
  ON public.recruitment_applications (applicant_number);
