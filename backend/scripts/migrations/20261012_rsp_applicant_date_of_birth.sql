-- Explicit upgrade for the date_of_birth field already used by RSP routes.
-- Existing applicants remain NULL; do not infer a birth date from their age.
ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;
