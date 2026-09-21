-- RSP/L&D schema additions merged on 2026-09-17.
-- Safe to re-run.
BEGIN;

CREATE TABLE IF NOT EXISTS public.learning_application_plan_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  memo_report_to TEXT,
  from_name TEXT,
  thru TEXT,
  subject TEXT,
  title TEXT,
  date TEXT,
  venue TEXT,
  cost TEXT,
  reap_types JSONB DEFAULT '[]'::JSONB,
  other_reap_type TEXT,
  reported_by TEXT,
  received_by TEXT,
  entries JSONB DEFAULT '[]'::JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ojt_work_immersion_evaluation_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ojt_immersion TEXT,
  school TEXT,
  interview_date TEXT,
  problem_solving_score INT,
  problem_solving_notes TEXT,
  communication_score INT,
  communication_notes TEXT,
  teamwork_score INT,
  teamwork_notes TEXT,
  adaptability_score INT,
  adaptability_notes TEXT,
  total_score INT,
  overall_recommendation TEXT,
  key_strengths TEXT,
  key_concerns TEXT,
  interviewer TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.form_print_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  module TEXT NOT NULL CHECK (module IN ('rsp', 'ld')),
  form_key TEXT NOT NULL,
  paper_size TEXT NOT NULL,
  file_path TEXT NOT NULL,
  original_filename TEXT,
  mime_type TEXT,
  uploaded_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (module, form_key)
);

ALTER TABLE public.recruitment_applications
  ADD COLUMN IF NOT EXISTS hire_credentials_email_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS hire_login_username TEXT,
  ADD COLUMN IF NOT EXISTS hire_login_password TEXT;

CREATE INDEX IF NOT EXISTS idx_learning_application_plan_entries_created
  ON public.learning_application_plan_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ojt_work_immersion_evaluation_entries_created
  ON public.ojt_work_immersion_evaluation_entries(created_at DESC);

COMMIT;
