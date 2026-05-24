-- Tracks when admin sent hire credentials email (RSP final hiring workflow).
-- Safe to re-run.
ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS hire_credentials_email_sent_at TIMESTAMPTZ;
