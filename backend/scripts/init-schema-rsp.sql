-- Run AFTER init-schema.sql (standalone - no FK to users)
-- Run: psql -d hrms_plaridel -f scripts/init-schema-rsp.sql

-- =========================
-- RSP - RECRUITMENT
-- =========================
CREATE TABLE IF NOT EXISTS recruitment_applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  resume_notes TEXT,
  attachment_path TEXT,
  attachment_name TEXT,
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (
      status IN (
        'submitted',
        'document_approved',
        'document_declined',
        'exam_taken',
        'passed',
        'failed',
        'registered'
      )
    ),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recruitment_exam_results (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id UUID NOT NULL REFERENCES recruitment_applications(id) ON DELETE CASCADE,
  score_percent NUMERIC(5,2) NOT NULL,
  passed BOOLEAN NOT NULL,
  answers_json JSONB,
  submitted_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure one exam result row per application
ALTER TABLE recruitment_exam_results
  ADD CONSTRAINT IF NOT EXISTS uq_recruitment_exam_results_application UNIQUE (application_id);

CREATE TABLE IF NOT EXISTS recruitment_exam_questions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exam_type TEXT NOT NULL,
  sort_order INT NOT NULL,
  question_text TEXT NOT NULL,
  options_json JSONB,
  correct_index INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_vacancy_announcement (
  id TEXT PRIMARY KEY DEFAULT 'default',
  has_vacancies BOOLEAN DEFAULT true,
  headline TEXT,
  body TEXT,
  vacancies JSONB DEFAULT '[]'::JSONB,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure a default row exists for landing page + admin RSP forms
INSERT INTO job_vacancy_announcement (id, has_vacancies, headline, body)
VALUES ('default', true, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS selection_lineup_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date TEXT,
  name_of_agency_office TEXT,
  vacant_position TEXT,
  item_no TEXT,
  applicants JSONB DEFAULT '[]',
  prepared_by_name TEXT,
  prepared_by_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS applicants_profile_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_applied_for TEXT,
  minimum_requirements TEXT,
  date_of_posting TEXT,
  closing_date TEXT,
  applicants JSONB DEFAULT '[]',
  prepared_by TEXT,
  checked_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS comparative_assessment_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_to_be_filled TEXT,
  min_req_education TEXT,
  min_req_experience TEXT,
  min_req_eligibility TEXT,
  min_req_training TEXT,
  candidates JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS promotion_certification_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_for_promotion TEXT,
  candidates JSONB DEFAULT '[]',
  date_day TEXT,
  date_month TEXT,
  date_year TEXT,
  signatory_name TEXT,
  signatory_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recruitment_applications_status
  ON recruitment_applications(status);

CREATE INDEX IF NOT EXISTS idx_recruitment_applications_created
  ON recruitment_applications(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_recruitment_exam_results_application
  ON recruitment_exam_results(application_id);

CREATE INDEX IF NOT EXISTS idx_recruitment_exam_questions_type
  ON recruitment_exam_questions(exam_type);

CREATE INDEX IF NOT EXISTS idx_job_vacancy_announcement_updated
  ON job_vacancy_announcement(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_selection_lineup_entries_created
  ON selection_lineup_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_applicants_profile_entries_created
  ON applicants_profile_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comparative_assessment_entries_created
  ON comparative_assessment_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_promotion_certification_entries_created
  ON promotion_certification_entries(created_at DESC);
