-- Custom RSP exams created by admins (name + open-ended / multiple-choice).
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.recruitment_custom_exams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exam_type TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  format TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recruitment_custom_exams_created
  ON public.recruitment_custom_exams(created_at DESC);
