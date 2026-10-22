-- HR interviewer e-sign stored on the OJT evaluation itself.
ALTER TABLE public.ojt_work_immersion_evaluation_entries
  ADD COLUMN IF NOT EXISTS interviewer_signature TEXT;
