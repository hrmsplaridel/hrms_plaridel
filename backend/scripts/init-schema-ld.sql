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
