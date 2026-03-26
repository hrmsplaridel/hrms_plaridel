-- HRMS Plaridel - L&D (Learning & Development) / RSP Forms
-- Run AFTER init-schema.sql (standalone)
-- Run: psql -d hrms_plaridel -f scripts/init-schema-ld.sql

-- =========================
-- L&D - RSP FORMS
-- =========================
CREATE TABLE IF NOT EXISTS bi_form_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  applicant_name TEXT NOT NULL,
  applicant_department TEXT,
  applicant_position TEXT,
  position_applied_for TEXT,
  respondent_name TEXT NOT NULL,
  respondent_position TEXT,
  respondent_relationship TEXT NOT NULL DEFAULT 'supervisor'
    CHECK (respondent_relationship IN ('supervisor', 'peer', 'subordinate')),
  rating_1 INT,
  rating_2 INT,
  rating_3 INT,
  rating_4 INT,
  rating_5 INT,
  rating_6 INT,
  rating_7 INT,
  rating_8 INT,
  rating_9 INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS performance_evaluation_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  applicant_name TEXT,
  functional_areas JSONB DEFAULT '[]'::JSONB,
  other_functional_area TEXT,
  performance_3_years TEXT,
  challenges_coping TEXT,
  compliance_attendance TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS training_need_analysis_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cy_year TEXT,
  department TEXT,
  rows JSONB DEFAULT '[]'::JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS action_brainstorming_coaching_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  department TEXT,
  date TEXT,
  rows JSONB DEFAULT '[]'::JSONB,
  certified_by TEXT,
  certification_date TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS turn_around_time_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position TEXT,
  office TEXT,
  no_of_vacant_position TEXT,
  date_of_publication TEXT,
  end_search TEXT,
  qs TEXT,
  applicants JSONB DEFAULT '[]'::JSONB,
  prepared_by_name TEXT,
  prepared_by_title TEXT,
  noted_by_name TEXT,
  noted_by_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS idp_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  position TEXT,
  category TEXT,
  division TEXT,
  department TEXT,
  education TEXT,
  experience TEXT,
  training TEXT,
  eligibility TEXT,
  target_position_1 TEXT,
  target_position_2 TEXT,
  avg_rating TEXT,
  opcr TEXT,
  ipcr TEXT,
  performance_rating TEXT,
  competency_description TEXT,
  competence_rating TEXT,
  succession_priority_score TEXT,
  succession_priority_rating TEXT,
  development_plan_rows JSONB DEFAULT '[]'::JSONB,
  prepared_by TEXT,
  reviewed_by TEXT,
  noted_by TEXT,
  approved_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- TRAINING DAILY REPORTS
-- =========================

CREATE TABLE IF NOT EXISTS training_daily_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  attachment_path TEXT,
  attachment_name TEXT,
  attachment_type TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'seen', 'reviewed', 'approved', 'needs_revision')),
  seen_by_admin UUID REFERENCES users(id) ON DELETE SET NULL,
  seen_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS training_report_attachments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_id UUID NOT NULL REFERENCES training_daily_reports(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================
-- INDEXES FOR L&D / RSP FORMS
-- =========================

CREATE INDEX IF NOT EXISTS idx_bi_form_entries_created
  ON bi_form_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_performance_evaluation_entries_created
  ON performance_evaluation_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_training_need_analysis_entries_created
  ON training_need_analysis_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_action_brainstorming_coaching_entries_created
  ON action_brainstorming_coaching_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_turn_around_time_entries_created
  ON turn_around_time_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_idp_entries_created
  ON idp_entries(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_training_daily_reports_employee_submitted
  ON training_daily_reports(employee_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_training_daily_reports_status
  ON training_daily_reports(status);

CREATE INDEX IF NOT EXISTS idx_training_report_attachments_report
  ON training_report_attachments(report_id, created_at DESC);

-- updated_at trigger for training_daily_reports
DROP TRIGGER IF EXISTS trg_training_daily_reports_updated_at ON training_daily_reports;
CREATE TRIGGER trg_training_daily_reports_updated_at
BEFORE UPDATE ON training_daily_reports
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();
